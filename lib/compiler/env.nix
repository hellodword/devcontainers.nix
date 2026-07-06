{ lib }:
{
  config,
  compiledEnvironment ? {
    variables = { };
    variableOrigins = { };
    remoteEnv = { };
    remoteEnvOrigins = { };
  },
  compiledFhsRuntime ? {
    env = { };
    envOrigins = { };
  },
  compiledLibraries ? {
    env = { };
    envOrigins = { };
  },
  compiledProfiles ? {
    env = {
      pathSegments = { };
      pathSegmentOrigins = { };
    };
  },
}:
let
  envUtils = import ./env-utils.nix { inherit lib; };
  order = config.devcontainer.path.order;
  pathSegments = lib.zipAttrsWith (_: values: lib.concatLists values) [
    config.devcontainer.path.segments
    compiledProfiles.env.pathSegments
  ];
  segmentOrigins =
    lib.zipAttrsWith
      (_: values: lib.zipAttrsWith (_: origins: lib.unique (lib.concatLists origins)) values)
      [
        config.devcontainer.path.segmentOrigins
        compiledProfiles.env.pathSegmentOrigins
      ];
  emptyOrigins = {
    container = { };
    remote = { };
    shell = { };
  };
  configuredEnvOrigins = {
    container = compiledEnvironment.variableOrigins or { };
    remote = compiledEnvironment.remoteEnvOrigins or { };
    shell = { };
  };
  fhsEnv = compiledFhsRuntime.env or { };
  fhsEnvOrigins = compiledFhsRuntime.envOrigins or emptyOrigins;
  librariesEnv = compiledLibraries.env or { };
  librariesEnvOrigins = compiledLibraries.envOrigins or emptyOrigins;
  mergeOriginScope =
    scope:
    let
      configured = configuredEnvOrigins.${scope} or { };
      fhsGenerated = fhsEnvOrigins.${scope} or { };
      libraryGenerated = librariesEnvOrigins.${scope} or { };
      names = lib.unique (
        builtins.attrNames configured
        ++ builtins.attrNames fhsGenerated
        ++ builtins.attrNames libraryGenerated
      );
    in
    lib.genAttrs names (
      name:
      lib.unique (
        (configured.${name} or [ ]) ++ (fhsGenerated.${name} or [ ]) ++ (libraryGenerated.${name} or [ ])
      )
    );
  envOrigins = {
    container = mergeOriginScope "container";
    remote = mergeOriginScope "remote";
    shell = mergeOriginScope "shell";
  };
  rawContainerEnv =
    (compiledEnvironment.variables or { })
    // (fhsEnv.container or { })
    // (librariesEnv.container or { });
  rawRemoteEnv =
    (compiledEnvironment.remoteEnv or { }) // (fhsEnv.remote or { }) // (librariesEnv.remote or { });
  rawShellEnv = (fhsEnv.shell or { }) // (librariesEnv.shell or { });
  defaultWorkspaceEnvValues = [
    "/workspaces/$DEVCONTAINER_WORKSPACE"
    "/workspaces/${"$"}{DEVCONTAINER_WORKSPACE}"
  ];
  lateBoundWorkspace = builtins.elem (rawContainerEnv.WORKSPACE or null) defaultWorkspaceEnvValues;
  workspace = {
    inherit lateBoundWorkspace;
    lateBound = lateBoundWorkspace;
    envName = "WORKSPACE";
    metadataValue = "\${containerWorkspaceFolder}";
    containerEnv = lateBoundContainerEnv;
    pathEntries = lateBoundPathEntries;
    pathSegments = lateBoundPathSegments;
  };
  workspaceReferenceSuffix =
    value:
    if !lateBoundWorkspace || !builtins.isString value then
      null
    else if value == "$WORKSPACE" || value == "\${WORKSPACE}" then
      ""
    else if lib.hasPrefix "$WORKSPACE/" value then
      "/" + lib.removePrefix "$WORKSPACE/" value
    else if lib.hasPrefix "\${WORKSPACE}/" value then
      "/" + lib.removePrefix "\${WORKSPACE}/" value
    else
      null;
  isWorkspaceReference = value: workspaceReferenceSuffix value != null;
  expandableContainerEnv =
    if lateBoundWorkspace then removeAttrs rawContainerEnv [ "WORKSPACE" ] else rawContainerEnv;
  # Docker image Env values are not shell-expanded at runtime.
  expandValue = env: value: envUtils.expandValue { inherit env value; };
  expandedContainerEnv = envUtils.expandEnv {
    env = expandableContainerEnv;
    scope = "container environment";
  };

  pathEntryState =
    lib.foldl'
      (
        state: bucket:
        let
          bucketSegments = pathSegments.${bucket} or [ ];
        in
        lib.foldl' (
          inner: segment:
          let
            expandedSegment = expandValue expandedContainerEnv segment;
            segmentSourceSet = segmentOrigins.${bucket}.${segment} or [ ];
            exists = builtins.hasAttr expandedSegment inner.entries;
            previous =
              if exists then
                builtins.getAttr expandedSegment inner.entries
              else
                {
                  segment = expandedSegment;
                  buckets = [ ];
                  sources = [ ];
                };
            updated = {
              segment = expandedSegment;
              buckets = lib.unique (previous.buckets ++ [ bucket ]);
              sources = lib.unique (previous.sources ++ segmentSourceSet);
            };
          in
          {
            order = if exists then inner.order else inner.order ++ [ expandedSegment ];
            entries = inner.entries // {
              ${expandedSegment} = updated;
            };
          }
        ) state bucketSegments
      )
      {
        order = [ ];
        entries = { };
      }
      order;
  pathEntries = map (segment: builtins.getAttr segment pathEntryState.entries) pathEntryState.order;
  uniqueSegments = map (entry: entry.segment) pathEntries;
  lateBoundPathEntries =
    if lateBoundWorkspace then
      builtins.filter (entry: isWorkspaceReference entry.segment) pathEntries
    else
      [ ];
  staticPathEntries =
    if lateBoundWorkspace then
      builtins.filter (entry: !(isWorkspaceReference entry.segment)) pathEntries
    else
      pathEntries;
  lateBoundPathSegments = map (entry: entry.segment) lateBoundPathEntries;
  staticPathSegments = map (entry: entry.segment) staticPathEntries;
  compiledPath = lib.concatStringsSep ":" staticPathSegments;
  runtimeCompiledPath = lib.concatStringsSep ":" uniqueSegments;
  lateBoundContainerEnv =
    if lateBoundWorkspace then
      lib.filterAttrs (_: value: isWorkspaceReference value) expandedContainerEnv
    else
      { };
  staticContainerEnv =
    if lateBoundWorkspace then
      lib.filterAttrs (_: value: !(isWorkspaceReference value)) expandedContainerEnv
    else
      expandedContainerEnv;
  mkEnvEntry =
    scope: name: value:
    let
      sources = lib.unique (envOrigins.${scope}.${name} or [ ]);
    in
    {
      inherit value sources;
      conflict = builtins.length sources > 1;
    };
  containerEnv = staticContainerEnv // {
    PATH = compiledPath;
  };
  runtimeContainerEnv = expandedContainerEnv // {
    PATH = runtimeCompiledPath;
  };
  remoteEnv = envUtils.expandEnvWithContext {
    context = runtimeContainerEnv;
    env = rawRemoteEnv;
    scope = "remote environment";
  };
  shellEnv = envUtils.expandEnvWithContext {
    context = runtimeContainerEnv // remoteEnv;
    env = rawShellEnv;
    scope = "shell environment";
  };
  containerEnvSources =
    lib.mapAttrs (name: value: mkEnvEntry "container" name value) containerEnv
    // {
      PATH = {
        value = compiledPath;
        sources = [ "compiler.env.path" ];
        conflict = false;
        pathEntries = staticPathEntries;
      };
    };
  remoteEnvSources = lib.mapAttrs (name: value: mkEnvEntry "remote" name value) remoteEnv;
  shellEnvSources = lib.mapAttrs (name: value: mkEnvEntry "shell" name value) shellEnv;
  conflicts = {
    container = lib.filterAttrs (_: entry: entry.conflict) containerEnvSources;
    remote = lib.filterAttrs (_: entry: entry.conflict) remoteEnvSources;
    shell = lib.filterAttrs (_: entry: entry.conflict) shellEnvSources;
    path = builtins.filter (entry: builtins.length entry.sources > 1) pathEntries;
  };
in
{
  pathOrder = order;
  pathEntries = pathEntries;
  pathSegments = uniqueSegments;
  runtimePathEntries = pathEntries;
  runtimePathSegments = uniqueSegments;
  runtimePATH = runtimeCompiledPath;
  staticPathEntries = staticPathEntries;
  staticPathSegments = staticPathSegments;
  staticPATH = compiledPath;
  PATH = compiledPath;
  containerEnv = containerEnv;
  runtimeContainerEnv = runtimeContainerEnv;
  lateBoundContainerEnv = lateBoundContainerEnv;
  containerEnvSources = containerEnvSources;
  remoteEnv = remoteEnv;
  remoteEnvSources = remoteEnvSources;
  shellEnv = shellEnv;
  shellEnvSources = shellEnvSources;
  conflicts = conflicts;
  workspace = workspace;
}
