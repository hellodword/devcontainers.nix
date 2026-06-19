{ lib }:
{ config }:
let
  order = config.devcontainer.path.order;
  segments =
    lib.concatMap
      (segmentName: config.devcontainer.path.segments.${segmentName} or [ ])
      order;
  uniqueSegments = lib.unique segments;
  compiledPath = lib.concatStringsSep ":" uniqueSegments;
in
{
  pathSegments = uniqueSegments;
  PATH = compiledPath;
  containerEnv = config.devcontainer.env.container // { PATH = compiledPath; };
  remoteEnv = config.devcontainer.env.remote;
  shellEnv = config.devcontainer.env.shell;
}
