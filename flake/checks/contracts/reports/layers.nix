{
  lib,
  images,
  contractLib,
  ...
}:

let
  requiredLayerLinks = [
    "/bin"
    "/lib"
    "/libexec"
    "/share"
    "/etc"
  ];
  layerMissingLinks =
    layer:
    builtins.filter (path: !(builtins.elem path (layer.build.pathsToLink or [ ]))) requiredLayerLinks;
  perImage = lib.mapAttrsToList (
    name: image:
    let
      layers = image.layers.layers;
      budget = image.layers.budget;
      layerGroups = map (layer: layer.group) layers;
      layerMembers = lib.unique (lib.concatMap (layer: layer.members or [ ]) layers);
      fontLayers = builtins.filter (layer: layer.group == "fonts-runtime") layers;
      profilesWithPackages = map (profile: profile.id) (
        builtins.filter (
          profile: (profile.packageCount or 0) > 0
        ) image.profiles.report.effectiveEnabledProfiles
      );
      missingProfileLayers = builtins.filter (
        profile: !(builtins.elem profile layerMembers)
      ) profilesWithPackages;
      invalidLayerBuilds =
        map
          (layer: {
            group = layer.group;
            missingLinks = layerMissingLinks layer;
            copyToRoot = layer.build.copyToRoot or false;
            pathCount = layer.pathCount or 0;
            extraOutputsIsList = builtins.isList (layer.build.extraOutputsToInstall or null);
          })
          (
            builtins.filter (
              layer:
              !(layer.build.copyToRoot or false)
              || (layer.pathCount or 0) < 1
              || layerMissingLinks layer != [ ]
              || !(builtins.isList (layer.build.extraOutputsToInstall or null))
            ) layers
          );
      checks = {
        budgetHasSemanticMax = (budget.semanticMax or null) == (budget.max or 0) - (budget.reserve or 0);
        layerCountWithinBudget = builtins.length layers <= budget.semanticMax;
        maxLayerSizePresent = contractLib.nonEmptyString (budget.maxLayerSize or null);
        layerGroupsMatchOrder = layerGroups == image.layers.order;
        allLayersBuildable = invalidLayerBuilds == [ ];
        oneFontsLayer = builtins.length fontLayers == 1;
        fontsLayerContainsRuntimeFonts =
          builtins.length fontLayers == 1
          && builtins.elem "runtime/fonts" ((builtins.head fontLayers).members or [ ]);
        packageProfilesHaveLayers = missingProfileLayers == [ ];
      };
    in
    {
      inherit name checks;
      details = {
        inherit
          invalidLayerBuilds
          missingProfileLayers
          ;
        layerGroups = layerGroups;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-layers = contractLib.mkAssertedJsonCheck "contracts-reports-layers" [ allValid ] {
    images = perImage;
  };
}
