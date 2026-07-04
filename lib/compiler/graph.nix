{ lib }:
{
  config,
  compiledProfiles ? {
    graphNodes = { };
  },
}:
let
  displayPathString = path: builtins.unsafeDiscardStringContext (toString path);
  normalizeNode = node: {
    kind = node.kind;
    group = node.group;
    target = node.target;
    stability = node.stability;
    sharing = node.sharing;
    priority = node.priority;
    securityClass = node.securityClass;
    paths = map displayPathString node.paths;
    files = node.files;
  };
  rawNodes = config.devcontainer.graph.nodes // compiledProfiles.graphNodes;
  nodes = lib.mapAttrs (_: normalizeNode) rawNodes;
  nodeNames = lib.sort lib.lessThan (builtins.attrNames nodes);
  groups = lib.foldl' (
    acc: name:
    let
      node = nodes.${name};
      current = acc.${node.group} or [ ];
    in
    acc // { ${node.group} = current ++ [ name ]; }
  ) { } nodeNames;
  pathNodePairs = lib.concatMap (
    name: map (path: { inherit name path; }) nodes.${name}.paths
  ) nodeNames;
  pathNodeIndex = lib.mapAttrs (_: value: lib.unique value) (
    lib.foldl' (
      acc: entry: acc // { ${entry.path} = (acc.${entry.path} or [ ]) ++ [ entry.name ]; }
    ) { } pathNodePairs
  );
  duplicates = lib.filterAttrs (_: value: builtins.length value > 1) (pathNodeIndex);
in
{
  inherit
    rawNodes
    nodes
    groups
    duplicates
    ;
}
