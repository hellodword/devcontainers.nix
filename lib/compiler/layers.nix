{ lib }:
{ config, compiledGraph }:
let
  bucketOrder = config.devcontainer.layers.buckets;
  layerNames =
    lib.filter
      (bucket: compiledGraph.groups ? ${bucket})
      bucketOrder;
  mkLayer =
    group:
    let
      members = compiledGraph.groups.${group};
      priority =
        lib.foldl'
          lib.max
          0
          (map (name: compiledGraph.nodes.${name}.priority) members);
      estimatedCompressedSizeMiB =
        builtins.length members * 32;
    in
    {
      inherit group members priority estimatedCompressedSizeMiB;
    };
in
{
  budget = {
    strategy = config.devcontainer.layers.strategy;
    max = config.devcontainer.layers.max;
    reserve = config.devcontainer.layers.reserve;
    maxCompressedLayerSize = config.devcontainer.layers.maxCompressedLayerSize;
  };
  layers = map mkLayer layerNames;
}
