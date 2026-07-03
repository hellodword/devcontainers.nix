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
  layerBudgetMax = config.devcontainer.layers.max;
  layerBudgetReserve = config.devcontainer.layers.reserve;
  semanticLayerMax = layerBudgetMax - layerBudgetReserve;
  budget =
    if layerBudgetMax < 1 then
      builtins.throw "devcontainer.layers.max must be at least 1"
    else if layerBudgetReserve < 0 then
      builtins.throw "devcontainer.layers.reserve must be non-negative"
    else if semanticLayerMax < 0 then
      builtins.throw "devcontainer.layers.reserve must be less than or equal to devcontainer.layers.max"
    else
      {
        strategy = config.devcontainer.layers.strategy;
        max = layerBudgetMax;
        reserve = layerBudgetReserve;
        semanticMax = semanticLayerMax;
        maxLayerSize = config.devcontainer.layers.maxLayerSize;
      };
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
  plannedLayers = map mkLayer nonEmptyLayerNames;
  checkedLayers =
    if builtins.length plannedLayers > budget.semanticMax then
      builtins.throw "semantic layer count ${toString (builtins.length plannedLayers)} exceeds budget ${toString budget.semanticMax} (devcontainer.layers.max - devcontainer.layers.reserve)"
    else
      plannedLayers;
in
{
  inherit budget;
  order = nonEmptyLayerNames;
  layers = checkedLayers;
}
