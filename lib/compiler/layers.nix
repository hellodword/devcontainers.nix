{ lib, pkgs }:
{
  config,
  compiledGraph,
  compiledEnvironment ? {
    pathsToLink = [
      "/bin"
      "/include"
      "/lib"
      "/lib64"
      "/libexec"
      "/share"
      "/etc"
    ];
    extraOutputsToInstall = [ ];
  },
}:
let
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  bucketOrder = config.devcontainer.layers.buckets;
  layerNames = lib.filter (bucket: compiledGraph.groups ? ${bucket}) bucketOrder;
  pathsForMembers =
    members: lib.unique (lib.concatMap (name: compiledGraph.rawNodes.${name}.paths) members);
  packageName = drv: drv.pname or drv.name or (builtins.baseNameOf (pathString drv));
  mkLayer =
    group:
    let
      members = compiledGraph.groups.${group};
      paths = pathsForMembers members;
      priority = lib.foldl' lib.max 0 (map (name: compiledGraph.nodes.${name}.priority) members);
      estimatedLayerSizeMiB = builtins.length paths * 32;
    in
    {
      inherit
        group
        members
        priority
        estimatedLayerSizeMiB
        ;
      pathCount = builtins.length paths;
      storePaths = map pathString paths;
      packages = map packageName paths;
      build = {
        copyToRoot = true;
        pathsToLink = compiledEnvironment.pathsToLink;
        extraOutputsToInstall = compiledEnvironment.extraOutputsToInstall;
        maxLayers = 1;
      };
    };
  nonEmptyLayerNames = builtins.filter (
    group: (pathsForMembers compiledGraph.groups.${group}) != [ ]
  ) layerNames;
in
{
  budget = {
    strategy = config.devcontainer.layers.strategy;
    max = config.devcontainer.layers.max;
    reserve = config.devcontainer.layers.reserve;
    maxLayerSize = config.devcontainer.layers.maxLayerSize;
  };
  order = nonEmptyLayerNames;
  layers = map mkLayer nonEmptyLayerNames;
}
