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
  # Docker image Env values are not shell-expanded at runtime.
  expandValue = env: value: envUtils.expandValue { inherit env value; };
  expandedContainerEnv = envUtils.expandEnv {
    env = rawContainerEnv;
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
  compiledPath = lib.concatStringsSep ":" uniqueSegments;
  mkEnvEntry =
    scope: name: value:
    let
      sources = lib.unique (envOrigins.${scope}.${name} or [ ]);
    in
    {
      inherit value sources;
      conflict = builtins.length sources > 1;
    };
  containerEnv = expandedContainerEnv // {
    PATH = compiledPath;
  };
  remoteEnv = envUtils.expandEnvWithContext {
    context = containerEnv;
    env = rawRemoteEnv;
    scope = "remote environment";
  };
  shellEnv = envUtils.expandEnvWithContext {
    context = containerEnv // remoteEnv;
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
        pathEntries = pathEntries;
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
  PATH = compiledPath;
  containerEnv = containerEnv;
  containerEnvSources = containerEnvSources;
  remoteEnv = remoteEnv;
  remoteEnvSources = remoteEnvSources;
  shellEnv = shellEnv;
  shellEnvSources = shellEnvSources;
  conflicts = conflicts;
}
