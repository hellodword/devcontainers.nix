{ lib, pkgs }:
{ config, compiledGraph }:
let
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  bucketOrder = config.devcontainer.layers.buckets;
  layerNames = lib.filter (bucket: compiledGraph.groups ? ${bucket}) bucketOrder;
  pathsForMembers =
    members: lib.unique (lib.concatMap (name: config.devcontainer.graph.nodes.${name}.paths) members);
  packageName = drv: drv.pname or drv.name or (builtins.baseNameOf (pathString drv));
  mkLayer =
    group:
    let
      members = compiledGraph.groups.${group};
      paths = pathsForMembers members;
      priority = lib.foldl' lib.max 0 (map (name: compiledGraph.nodes.${name}.priority) members);
      estimatedCompressedSizeMiB = builtins.length paths * 32;
    in
    {
      inherit
        group
        members
        priority
        estimatedCompressedSizeMiB
        ;
      pathCount = builtins.length paths;
      storePaths = map pathString paths;
      packages = map packageName paths;
      build = {
        copyToRoot = true;
        pathsToLink = [
          "/bin"
          "/sbin"
          "/lib"
          "/lib64"
          "/share"
          "/etc"
        ];
        maxLayers = 1;
      };
    };
in
{
  budget = {
    strategy = config.devcontainer.layers.strategy;
    max = config.devcontainer.layers.max;
    reserve = config.devcontainer.layers.reserve;
    maxCompressedLayerSize = config.devcontainer.layers.maxCompressedLayerSize;
  };
  order = layerNames;
  layers = map mkLayer layerNames;
}
