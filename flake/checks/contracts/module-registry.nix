{
  pkgs,
  lib,
  compiler,
  ...
}:

let
  moduleRoot = ../../../lib/modules;
  moduleRegistry = import moduleRoot { inherit lib; };
  categories = [
    "core"
    "editor"
    "programs"
    "toolsets"
    "tools"
    "runtimes"
    "languages"
  ];
  isModuleFile =
    name: type:
    type == "regular"
    && lib.hasSuffix ".nix" name
    && name != "default.nix"
    && !(lib.hasPrefix "." name)
    && !(lib.hasSuffix "~" name)
    && !(lib.hasSuffix ".bak.nix" name)
    && !(lib.hasSuffix ".orig.nix" name);
  expectedFileNamesByCategory = lib.listToAttrs (
    map (
      category:
      lib.nameValuePair category (
        lib.sort lib.lessThan (
          builtins.attrNames (lib.filterAttrs isModuleFile (builtins.readDir (moduleRoot + "/${category}")))
        )
      )
    ) categories
  );
  qualifyFileNames =
    namesByCategory:
    lib.concatMap (category: map (name: "${category}/${name}") namesByCategory.${category}) categories;
  expectedFileNames = qualifyFileNames expectedFileNamesByCategory;
  actualFileNames = qualifyFileNames moduleRegistry.moduleFileNamesByCategory;
  expectedModulePaths = map (fileName: toString (moduleRoot + "/${fileName}")) expectedFileNames;
  actualModulePaths = map toString moduleRegistry.allModules;

  evaluated = compiler.evalImage {
    modules = [
      (
        { lib, ... }:
        {
          config.devcontainer.image.name = lib.mkForce "bucket-registry-contract";
        }
      )
    ];
  };
  config = evaluated.config;

  duplicateValues =
    values:
    lib.unique (
      builtins.filter (
        value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
      ) values
    );
  sortEntries = lib.sort (
    a: b: if a.order != b.order then a.order < b.order else lib.lessThan a.name b.name
  );
  isOrderMultipleOf10 = order: order - (builtins.div order 10) * 10 == 0;
  definitionEntries =
    definitions:
    lib.mapAttrsToList (
      name: definition:
      definition
      // {
        inherit name;
      }
    ) definitions;
  definitionSummary = entry: {
    inherit (entry)
      name
      order
      owner
      purpose
      ;
  };
  invalidOrderNames =
    entries: predicate:
    map (entry: entry.name) (builtins.filter (entry: predicate entry.order) entries);

  layerDefinitions = config.devcontainer.layers.bucketDefinitions;
  layerEntries = definitionEntries layerDefinitions;
  layerDefinitionNames = builtins.attrNames layerDefinitions;
  layerDefinitionOrderValues = map (entry: entry.order) layerEntries;
  derivedLayerBuckets = map (entry: entry.name) (sortEntries layerEntries);
  layerDefinitionSummaries = map definitionSummary (sortEntries layerEntries);
  emptyLayerBucketNames = builtins.filter (name: name == "") layerDefinitionNames;
  invalidLayerNegativeOrders = invalidOrderNames layerEntries (order: order < 0);
  invalidLayerOrderGranularity = invalidOrderNames layerEntries (order: !(isOrderMultipleOf10 order));
  duplicateLayerDefinitionOrders = duplicateValues layerDefinitionOrderValues;

  pathDefinitions = config.devcontainer.path.bucketDefinitions;
  pathEntries = definitionEntries pathDefinitions;
  pathDefinitionNames = builtins.attrNames pathDefinitions;
  pathDefinitionOrderValues = map (entry: entry.order) pathEntries;
  derivedPathOrder = map (entry: entry.name) (sortEntries pathEntries);
  pathDefinitionSummaries = map definitionSummary (sortEntries pathEntries);
  derivedPathSegments = lib.mapAttrs (_: definition: definition.segments) pathDefinitions;
  derivedPathSegmentOrigins = lib.mapAttrs (_: definition: definition.segmentOrigins) pathDefinitions;
  emptyPathBucketNames = builtins.filter (name: name == "") pathDefinitionNames;
  invalidPathNegativeOrders = invalidOrderNames pathEntries (order: order < 0);
  invalidPathOrderGranularity = invalidOrderNames pathEntries (order: !(isOrderMultipleOf10 order));
  duplicatePathDefinitionOrders = duplicateValues pathDefinitionOrderValues;

  profiles = builtins.attrValues config.devcontainer.profiles;
  profileGroups = lib.unique (map (profile: profile.group) profiles);
  profilePathBuckets = lib.unique (map (profile: profile.env.pathBucket) profiles);
  extensionBuckets = lib.unique (
    lib.concatMap (
      profile: map (extension: extension.bucket) (builtins.attrValues profile.vscode.extensions)
    ) profiles
  );
  missingProfileGroupDefinitions = builtins.filter (
    group: !(builtins.hasAttr group layerDefinitions)
  ) profileGroups;
  missingExtensionBucketDefinitions = builtins.filter (
    bucket: !(builtins.hasAttr bucket layerDefinitions)
  ) extensionBuckets;
  missingPathBucketDefinitions = builtins.filter (
    bucket: !(builtins.hasAttr bucket pathDefinitions)
  ) profilePathBuckets;
in
{
  contracts-module-registry =
    assert moduleRegistry.categories == categories;
    assert expectedFileNames == actualFileNames;
    assert expectedModulePaths == actualModulePaths;
    pkgs.writeText "contracts-module-registry.json" (
      builtins.toJSON {
        inherit
          categories
          expectedFileNames
          actualFileNames
          ;
      }
    );

  contracts-bucket-registry =
    assert emptyLayerBucketNames == [ ];
    assert emptyPathBucketNames == [ ];
    assert invalidLayerNegativeOrders == [ ];
    assert invalidPathNegativeOrders == [ ];
    assert invalidLayerOrderGranularity == [ ];
    assert invalidPathOrderGranularity == [ ];
    assert duplicateLayerDefinitionOrders == [ ];
    assert duplicatePathDefinitionOrders == [ ];
    assert config.devcontainer.layers.buckets == derivedLayerBuckets;
    assert config.devcontainer.path.order == derivedPathOrder;
    assert config.devcontainer.path.segments == derivedPathSegments;
    assert config.devcontainer.path.segmentOrigins == derivedPathSegmentOrigins;
    assert missingProfileGroupDefinitions == [ ];
    assert missingExtensionBucketDefinitions == [ ];
    assert missingPathBucketDefinitions == [ ];
    pkgs.writeText "contracts-bucket-registry.json" (
      builtins.toJSON {
        layers = {
          definitions = layerDefinitionSummaries;
          derivedOrder = derivedLayerBuckets;
        };
        path = {
          definitions = pathDefinitionSummaries;
          derivedOrder = derivedPathOrder;
        };
        validation = {
          inherit
            invalidLayerNegativeOrders
            invalidPathNegativeOrders
            invalidLayerOrderGranularity
            invalidPathOrderGranularity
            missingProfileGroupDefinitions
            missingExtensionBucketDefinitions
            missingPathBucketDefinitions
            ;
        };
      }
    );
}
