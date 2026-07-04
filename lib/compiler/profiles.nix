{ lib }:
{ config }:
let
  displayPathString = path: builtins.unsafeDiscardStringContext (toString path);
  packageName = drv: drv.pname or drv.name or (builtins.baseNameOf (displayPathString drv));

  bucketOrder = config.devcontainer.layers.buckets;
  bucketRanks = lib.listToAttrs (
    lib.imap0 (index: bucket: lib.nameValuePair bucket index) bucketOrder
  );
  bucketRank = group: bucketRanks.${group} or 999999;
  duplicateValues =
    values:
    let
      counts = lib.foldl' (
        acc: value:
        acc
        // {
          ${value} = (acc.${value} or 0) + 1;
        }
      ) { } values;
      state =
        lib.foldl'
          (
            acc: value:
            if (counts.${value} or 0) > 1 && !(builtins.hasAttr value acc.seen) then
              {
                seen = acc.seen // {
                  ${value} = true;
                };
                valuesRev = [ value ] ++ acc.valuesRev;
              }
            else
              acc
          )
          {
            seen = { };
            valuesRev = [ ];
          }
          values;
    in
    lib.reverseList state.valuesRev;
  sortProfiles = lib.sort (
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
  );

  allProfiles = lib.mapAttrsToList (_: profile: profile) config.devcontainer.profiles;
  allProfileIds = map (profile: profile.id) allProfiles;
  duplicateProfileIds = duplicateValues allProfileIds;
  profileById = lib.listToAttrs (map (profile: lib.nameValuePair profile.id profile) allProfiles);
  rootProfiles = sortProfiles (builtins.filter (profile: profile.enable) allProfiles);
  rootEnabledIds = map (profile: profile.id) rootProfiles;

  expandProfile =
    stack: id:
    if !(builtins.hasAttr id profileById) then
      builtins.throw "devcontainer.profiles includes unknown profile ${id} from ${lib.concatStringsSep " -> " stack}"
    else if builtins.elem id stack then
      builtins.throw "devcontainer.profiles include cycle: ${
        lib.concatStringsSep " -> " (stack ++ [ id ])
      }"
    else
      let
        profile = profileById.${id};
      in
      [ id ] ++ lib.concatMap (child: expandProfile (stack ++ [ id ]) child) profile.includes;

  effectiveIds = lib.unique (lib.concatMap (id: expandProfile [ ] id) rootEnabledIds);
  sortedProfiles = sortProfiles (map (id: profileById.${id}) effectiveIds);
  enabledIds = map (profile: profile.id) sortedProfiles;

  profileEnvIsEmpty =
    profile:
    profile.env.variables == { }
    && profile.env.remoteVariables == { }
    && profile.env.path == [ ]
    && profile.env.aliases == { }
    && profile.env.shellInit == ""
    && profile.env.interactiveShellInit == "";
  profileHasBundleResources =
    profile:
    profile.packages != [ ]
    || profile.provides.commands != [ ]
    || profile.vscode.extensions != { }
    || profile.vscode.settings != { }
    || !(profileEnvIsEmpty profile)
    || profile.libraries.presets != [ ]
    || profile.lifecycle.tasks != { }
    || profile.tests.cases != { };
  leafProfilesWithIncludes = map (profile: profile.id) (
    builtins.filter (profile: profile.composition.role == "leaf" && profile.includes != [ ]) allProfiles
  );
  bundleProfilesWithResources = map (profile: profile.id) (
    builtins.filter (
      profile: profile.composition.role == "bundle" && profileHasBundleResources profile
    ) allProfiles
  );

  includeEdges = lib.concatMap (
    parent:
    map (child: {
      inherit parent child;
    }) profileById.${parent}.includes
  ) effectiveIds;
  includedBy =
    id:
    lib.sort lib.lessThan (
      lib.unique (map (edge: edge.parent) (builtins.filter (edge: edge.child == id) includeEdges))
    );
  includeGraph = lib.listToAttrs (
    map (id: lib.nameValuePair id profileById.${id}.includes) (lib.sort lib.lessThan effectiveIds)
  );

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
  duplicateExtensionOwners =
    lib.mapAttrsToList
      (extensionId: entries: {
        inherit extensionId;
        origins = lib.unique (map (entry: entry.profileId) entries);
      })
      (
        lib.filterAttrs (
          _: entries: builtins.length (lib.unique (map (entry: entry.profileId) entries)) > 1
        ) groupedExtensionEntries
      );

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
      required = singleValue "required" extensionId entries;
      inherit bucket;
      companionTools = lib.unique (lib.concatMap (entry: entry.companionTools) entries);
      projectionOverride = nullableValue "projectionOverride" extensionId entries;
      sourcePreference = singleValue "sourcePreference" extensionId entries;
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

  profileCaseEntries = lib.concatMap (
    profile:
    lib.mapAttrsToList (caseId: case: {
      id = caseId;
      inherit case;
      profileId = profile.id;
    }) profile.tests.cases
  ) sortedProfiles;
  groupedCaseEntries = lib.groupBy (entry: entry.id) profileCaseEntries;
  conflictingCaseEntries =
    lib.mapAttrsToList
      (caseId: entries: {
        inherit caseId;
        profileIds = map (entry: entry.profileId) entries;
      })
      (
        lib.filterAttrs (
          _: entries: builtins.length (lib.unique (map (entry: entry.case) entries)) > 1
        ) groupedCaseEntries
      );
  testCases = lib.mapAttrs (_: entries: (builtins.head entries).case) groupedCaseEntries;
  testCaseIds = lib.sort lib.lessThan (builtins.attrNames testCases);
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

  mkProfileReport = profile: {
    inherit (profile)
      id
      kind
      group
      priority
      stability
      sharing
      securityClass
      ;
    composition = {
      role = profile.composition.role;
    };
    includes = profile.includes;
    includedBy = includedBy profile.id;
    rootEnabled = builtins.elem profile.id rootEnabledIds;
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
      cases = lib.sort lib.lessThan (builtins.attrNames profile.tests.cases);
    };
  };
  rootProfileReports = map mkProfileReport rootProfiles;
  profileReports = map mkProfileReport sortedProfiles;

  report = {
    rootEnabledProfiles = rootProfileReports;
    rootEnabledProfileIds = rootEnabledIds;
    effectiveEnabledProfiles = profileReports;
    effectiveEnabledProfileIds = enabledIds;
    includeGraph = includeGraph;
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
      cases = testCaseIds;
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
  builtins.throw "devcontainer.profiles contains duplicate profile ids: ${lib.concatStringsSep ", " duplicateProfileIds}"
else if leafProfilesWithIncludes != [ ] then
  builtins.throw "devcontainer.profiles leaf profiles cannot declare includes: ${lib.concatStringsSep ", " leafProfilesWithIncludes}"
else if bundleProfilesWithResources != [ ] then
  builtins.throw "devcontainer.profiles bundle profiles cannot declare packages, commands, VS Code extensions/settings, env, library presets, lifecycle tasks, or smoke cases: ${lib.concatStringsSep ", " bundleProfilesWithResources}"
else if unknownProfileGroups != [ ] then
  builtins.throw "devcontainer.profiles contains groups not present in devcontainer.layers.buckets: ${lib.concatStringsSep ", " unknownProfileGroups}"
else if unknownPathBuckets != [ ] then
  builtins.throw "devcontainer.profiles contains PATH buckets not present in devcontainer.path.order: ${lib.concatStringsSep ", " unknownPathBuckets}"
else if unknownExtensionBuckets != [ ] then
  builtins.throw "devcontainer.profiles contains VS Code extension buckets not present in devcontainer.layers.buckets: ${lib.concatStringsSep ", " unknownExtensionBuckets}"
else if duplicateExtensionOwners != [ ] then
  builtins.throw "devcontainer.profiles declares duplicate VS Code extension owners: ${builtins.toJSON duplicateExtensionOwners}"
else if duplicateTaskNames != [ ] then
  builtins.throw "devcontainer.profiles declares duplicate lifecycle task names: ${lib.concatStringsSep ", " duplicateTaskNames}"
else if conflictingCaseEntries != [ ] then
  builtins.throw "devcontainer.profiles declares conflicting smoke cases: ${builtins.toJSON conflictingCaseEntries}"
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
      testCases
      testCaseIds
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
