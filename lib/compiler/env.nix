{ lib }:
{
  config,
  compiledFhsRuntime ? {
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
  configuredEnvOrigins = config.devcontainer.env.origins or emptyOrigins;
  fhsEnv = compiledFhsRuntime.env or { };
  fhsEnvOrigins = compiledFhsRuntime.envOrigins or emptyOrigins;
  mergeOriginScope =
    scope:
    let
      configured = configuredEnvOrigins.${scope} or { };
      generated = fhsEnvOrigins.${scope} or { };
      names = lib.unique (builtins.attrNames configured ++ builtins.attrNames generated);
    in
    lib.genAttrs names (name: lib.unique ((configured.${name} or [ ]) ++ (generated.${name} or [ ])));
  envOrigins = {
    container = mergeOriginScope "container";
    remote = mergeOriginScope "remote";
    shell = mergeOriginScope "shell";
  };

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
            segmentSourceSet = segmentOrigins.${bucket}.${segment} or [ ];
            exists = builtins.hasAttr segment inner.entries;
            previous =
              if exists then
                builtins.getAttr segment inner.entries
              else
                {
                  inherit segment;
                  buckets = [ ];
                  sources = [ ];
                };
            updated = {
              inherit segment;
              buckets = lib.unique (previous.buckets ++ [ bucket ]);
              sources = lib.unique (previous.sources ++ segmentSourceSet);
            };
          in
          {
            order = if exists then inner.order else inner.order ++ [ segment ];
            entries = inner.entries // {
              ${segment} = updated;
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
  containerEnv =
    config.devcontainer.env.container
    // (fhsEnv.container or { })
    // {
      PATH = compiledPath;
    };
  remoteEnv = config.devcontainer.env.remote // (fhsEnv.remote or { });
  shellEnv = config.devcontainer.env.shell // (fhsEnv.shell or { });
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
