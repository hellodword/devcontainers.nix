{ lib }:
{ config }:
let
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  packageName = drv: drv.pname or drv.name or (builtins.baseNameOf (pathString drv));

  bucketOrder = config.devcontainer.layers.buckets;
  bucketRanks = lib.listToAttrs (
    lib.imap0 (index: bucket: lib.nameValuePair bucket index) bucketOrder
  );
  bucketRank = group: bucketRanks.${group} or 999999;
  duplicateValues =
    values:
    lib.unique (
      builtins.filter (
        value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
      ) values
    );

  enabledAttrs = lib.filterAttrs (_: profile: profile.enable) config.devcontainer.profiles;
  unsortedProfiles = lib.mapAttrsToList (_: profile: profile) enabledAttrs;
  sortedProfiles = lib.sort (
    a: b:
    let
      groupA = bucketRank a.group;
      groupB = bucketRank b.group;
    in
    if groupA != groupB then
      groupA < groupB
    else if a.priority != b.priority then
      a.priority > b.priority
    else
      a.id < b.id
  ) unsortedProfiles;

  enabledIds = map (profile: profile.id) sortedProfiles;
  duplicateProfileIds = duplicateValues enabledIds;
  unknownProfileGroups = lib.unique (
    builtins.filter (group: !(builtins.hasAttr group bucketRanks)) (
      map (profile: profile.group) sortedProfiles
    )
  );
  unknownPathBuckets = lib.unique (
    builtins.filter (bucket: !(builtins.elem bucket config.devcontainer.path.order)) (
      map (profile: profile.env.pathBucket) (
        builtins.filter (profile: profile.env.path != [ ]) sortedProfiles
      )
    )
  );

  extensionEntries = lib.concatMap (
    profile:
    lib.mapAttrsToList (
      _: extension:
      extension
      // {
        profileId = profile.id;
      }
    ) profile.vscode.extensions
  ) sortedProfiles;
  groupedExtensionEntries = lib.groupBy (entry: entry.id) extensionEntries;

  singleValue =
    field: extensionId: entries:
    let
      values = lib.unique (map (entry: entry.${field}) entries);
    in
    if builtins.length values == 1 then
      builtins.head values
    else
      builtins.throw "VS Code extension ${extensionId} declares conflicting ${field} metadata across profiles";
  nullableValue =
    field: extensionId: entries:
    let
      values = lib.unique (builtins.filter (value: value != null) (map (entry: entry.${field}) entries));
    in
    if builtins.length values <= 1 then
      if values == [ ] then null else builtins.head values
    else
      builtins.throw "VS Code extension ${extensionId} declares conflicting ${field} metadata across profiles";
  mkExtension =
    extensionId: entries:
    let
      bucket = singleValue "bucket" extensionId entries;
    in
    {
      id = extensionId;
      native = singleValue "native" extensionId entries;
      inherit bucket;
      companionTools = lib.unique (lib.concatMap (entry: entry.companionTools) entries);
      projectionOverride = nullableValue "projectionOverride" extensionId entries;
      sourcePreference = singleValue "sourcePreference" extensionId entries;
      required = builtins.all (entry: entry.required) entries;
      notes = lib.unique (builtins.filter (note: note != null) (map (entry: entry.notes) entries));
      origins = lib.unique (map (entry: entry.profileId) entries);
    };
  extensions = lib.mapAttrs mkExtension groupedExtensionEntries;
  extensionIds = lib.sort lib.lessThan (builtins.attrNames extensions);
  unknownExtensionBuckets = lib.unique (
    builtins.filter (bucket: !(builtins.hasAttr bucket bucketRanks)) (
      map (extension: extension.bucket) (builtins.attrValues extensions)
    )
  );

  mergeProfileAttrs =
    attrSelector:
    lib.foldl'
      (
        acc: profile:
        let
          attrs = attrSelector profile;
        in
        lib.foldl' (inner: name: {
          values = inner.values // {
            ${name} = attrs.${name};
          };
          origins = inner.origins // {
            ${name} = lib.unique ((inner.origins.${name} or [ ]) ++ [ profile.id ]);
          };
        }) acc (builtins.attrNames attrs)
      )
      {
        values = { };
        origins = { };
      }
      sortedProfiles;
  profileVariables = mergeProfileAttrs (profile: profile.env.variables);
  profileRemoteVariables = mergeProfileAttrs (profile: profile.env.remoteVariables);
  profileAliases = mergeProfileAttrs (profile: profile.env.aliases);

  pathContribution =
    lib.foldl'
      (
        acc: profile:
        let
          bucket = profile.env.pathBucket;
        in
        lib.foldl' (inner: segment: {
          segments = inner.segments // {
            ${bucket} = (inner.segments.${bucket} or [ ]) ++ [ segment ];
          };
          origins = inner.origins // {
            ${bucket} = (inner.origins.${bucket} or { }) // {
              ${segment} = lib.unique (((inner.origins.${bucket} or { }).${segment} or [ ]) ++ [ profile.id ]);
            };
          };
        }) acc profile.env.path
      )
      {
        segments = { };
        origins = { };
      }
      sortedProfiles;

  settings = lib.foldl' (
    acc: profile: lib.recursiveUpdate acc profile.vscode.settings
  ) { } sortedProfiles;

  taskEntries = lib.concatMap (
    profile:
    map (name: {
      inherit name profile;
      task = profile.lifecycle.tasks.${name};
    }) (builtins.attrNames profile.lifecycle.tasks)
  ) sortedProfiles;
  duplicateTaskNames = duplicateValues (map (entry: entry.name) taskEntries);
  tasks = lib.listToAttrs (map (entry: lib.nameValuePair entry.name entry.task) taskEntries);

  testCapabilities = lib.concatMap (profile: profile.tests.capabilities) sortedProfiles;
  packages = lib.concatMap (profile: profile.packages) sortedProfiles;
  packageNames = map packageName packages;
  providedCommands = lib.unique (lib.concatMap (profile: profile.provides.commands) sortedProfiles);
  libraryPresets = lib.unique (lib.concatMap (profile: profile.libraries.presets) sortedProfiles);

  extensionCompanionMisses = lib.concatMap (
    extension:
    map (tool: {
      extension = extension.id;
      companionTool = tool;
    }) (builtins.filter (tool: !(builtins.elem tool providedCommands)) extension.companionTools)
  ) (builtins.attrValues extensions);

  graphNodes = lib.listToAttrs (
    map (
      profile:
      lib.nameValuePair profile.id {
        inherit (profile)
          kind
          group
          packages
          stability
          sharing
          priority
          securityClass
          ;
        paths = profile.packages;
        files = { };
        target = "host";
        source = "profile";
      }
    ) sortedProfiles
  );

  profileReports = map (profile: {
    inherit (profile)
      id
      kind
      group
      priority
      stability
      sharing
      securityClass
      ;
    packageCount = builtins.length profile.packages;
    packages = map packageName profile.packages;
    provides = profile.provides;
    vscode = {
      extensions = lib.sort lib.lessThan (builtins.attrNames profile.vscode.extensions);
      settings = profile.vscode.settings;
    };
    env = {
      variables = profile.env.variables;
      remoteVariables = profile.env.remoteVariables;
      path = profile.env.path;
      pathBucket = profile.env.pathBucket;
      aliases = profile.env.aliases;
      hasShellInit = profile.env.shellInit != "";
      hasInteractiveShellInit = profile.env.interactiveShellInit != "";
    };
    libraries = {
      presets = profile.libraries.presets;
    };
    lifecycle = {
      tasks = lib.sort lib.lessThan (builtins.attrNames profile.lifecycle.tasks);
    };
    tests = {
      capabilities = profile.tests.capabilities;
    };
  }) sortedProfiles;

  report = {
    enabledProfiles = profileReports;
    packages = packageNames;
    provides = {
      commands = providedCommands;
    };
    extensions = map (id: extensions.${id}) extensionIds;
    vscode = {
      extensionIds = extensionIds;
      settings = settings;
    };
    env = {
      variables = profileVariables.values;
      remoteVariables = profileRemoteVariables.values;
      pathSegments = pathContribution.segments;
      aliases = profileAliases.values;
    };
    libraries = {
      presets = libraryPresets;
    };
    lifecycle = {
      tasks = lib.sort lib.lessThan (builtins.attrNames tasks);
    };
    tests = {
      capabilities = testCapabilities;
    };
    graph = {
      nodes = builtins.attrNames graphNodes;
    };
    validation = {
      companionToolsProvidedByNix = extensionCompanionMisses == [ ];
      missingCompanionTools = extensionCompanionMisses;
    };
  };
in
if duplicateProfileIds != [ ] then
  builtins.throw "devcontainer.profiles contains duplicate enabled profile ids: ${lib.concatStringsSep ", " duplicateProfileIds}"
else if unknownProfileGroups != [ ] then
  builtins.throw "devcontainer.profiles contains groups not present in devcontainer.layers.buckets: ${lib.concatStringsSep ", " unknownProfileGroups}"
else if unknownPathBuckets != [ ] then
  builtins.throw "devcontainer.profiles contains PATH buckets not present in devcontainer.path.order: ${lib.concatStringsSep ", " unknownPathBuckets}"
else if unknownExtensionBuckets != [ ] then
  builtins.throw "devcontainer.profiles contains VS Code extension buckets not present in devcontainer.layers.buckets: ${lib.concatStringsSep ", " unknownExtensionBuckets}"
else if duplicateTaskNames != [ ] then
  builtins.throw "devcontainer.profiles declares duplicate lifecycle task names: ${lib.concatStringsSep ", " duplicateTaskNames}"
else if extensionCompanionMisses != [ ] then
  builtins.throw "devcontainer.profiles has VS Code companion tools that are not provided by enabled profile packages: ${builtins.toJSON extensionCompanionMisses}"
else
  {
    enabled = sortedProfiles;
    ids = enabledIds;
    inherit
      packages
      packageNames
      graphNodes
      extensions
      extensionIds
      settings
      tasks
      testCapabilities
      libraryPresets
      providedCommands
      report
      ;
    env = {
      variables = profileVariables.values;
      variableOrigins = profileVariables.origins;
      remoteVariables = profileRemoteVariables.values;
      remoteVariableOrigins = profileRemoteVariables.origins;
      aliases = profileAliases.values;
      aliasOrigins = profileAliases.origins;
      shellInit = lib.concatStringsSep "\n" (
        builtins.filter (value: value != "") (map (profile: profile.env.shellInit) sortedProfiles)
      );
      interactiveShellInit = lib.concatStringsSep "\n" (
        builtins.filter (value: value != "") (
          map (profile: profile.env.interactiveShellInit) sortedProfiles
        )
      );
      pathSegments = pathContribution.segments;
      pathSegmentOrigins = pathContribution.origins;
    };
  }
