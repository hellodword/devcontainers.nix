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
}:
let
  order = config.devcontainer.path.order;
  segmentOrigins = config.devcontainer.path.segmentOrigins;
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
  expandValue =
    env: value:
    let
      names = lib.sort (a: b: builtins.stringLength a > builtins.stringLength b) (builtins.attrNames env);
      replaceName =
        current: name:
        let
          replacement = builtins.getAttr name env;
          braced = "$" + "{" + name + "}";
          plain = "$" + name;
          withBraced = builtins.replaceStrings [ braced ] [ replacement ] current;
          withDelimited =
            builtins.replaceStrings
              [
                (plain + "/")
                (plain + ":")
                (plain + ".")
                (plain + "-")
                (plain + "_")
              ]
              [
                (replacement + "/")
                (replacement + ":")
                (replacement + ".")
                (replacement + "-")
                (replacement + "_")
              ]
              withBraced;
        in
        if !(builtins.isString current) || !(builtins.isString replacement) then
          current
        else if withDelimited == plain then
          replacement
        else
          withDelimited;
    in
    if builtins.isString value then lib.foldl' replaceName value names else value;
  expandEnv =
    env:
    let
      step = current: lib.mapAttrs (_: value: expandValue current value) current;
      go =
        remaining: current:
        let
          next = step current;
        in
        if remaining == 0 || next == current then next else go (remaining - 1) next;
    in
    go 8 env;
  expandEnvWithContext =
    context: env:
    let
      expanded = expandEnv (context // env);
    in
    lib.genAttrs (builtins.attrNames env) (name: builtins.getAttr name expanded);
  expandedContainerEnv = expandEnv rawContainerEnv;

  pathEntryState =
    lib.foldl'
      (
        state: bucket:
        let
          bucketSegments = config.devcontainer.path.segments.${bucket} or [ ];
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
  remoteEnv = expandEnvWithContext containerEnv rawRemoteEnv;
  shellEnv = expandEnvWithContext (containerEnv // remoteEnv) rawShellEnv;
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
