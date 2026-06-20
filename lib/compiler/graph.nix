{ lib }:
{
  config,
  compiledProfiles ? {
    graphNodes = { };
  },
}:
let
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  normalizeNode = node: {
    kind = node.kind;
    group = node.group;
    target = node.target;
    stability = node.stability;
    sharing = node.sharing;
    priority = node.priority;
    securityClass = node.securityClass;
    paths = map pathString node.paths;
    files = node.files;
  };
  rawNodes = config.devcontainer.graph.nodes // compiledProfiles.graphNodes;
  nodes = lib.mapAttrs (_: normalizeNode) rawNodes;
  groups = lib.foldl' (
    acc: name:
    let
      node = nodes.${name};
      current = acc.${node.group} or [ ];
    in
    acc // { ${node.group} = current ++ [ name ]; }
  ) { } (lib.sort lib.lessThan (builtins.attrNames nodes));
  duplicates = lib.filterAttrs (_: value: builtins.length value > 1) (
    lib.mapAttrs (_: value: lib.unique value) (lib.mapAttrs (_: node: node.paths) nodes)
  );
in
{
  inherit
    rawNodes
    nodes
    groups
    duplicates
    ;
}
