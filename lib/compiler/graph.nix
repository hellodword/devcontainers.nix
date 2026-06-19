{ lib }:
{ config }:
let
  normalizeNode =
    node:
    {
      kind = node.kind;
      group = node.group;
      target = node.target;
      stability = node.stability;
      sharing = node.sharing;
      priority = node.priority;
      securityClass = node.securityClass;
      paths = map toString node.paths;
      files = node.files;
    };
  nodes = lib.mapAttrs (_: normalizeNode) config.devcontainer.graph.nodes;
  groups =
    lib.foldl'
      (acc: name:
        let
          node = nodes.${name};
          current = acc.${node.group} or [ ];
        in
        acc // { ${node.group} = current ++ [ name ]; })
      { }
      (lib.sort lib.lessThan (builtins.attrNames nodes));
  duplicates =
    lib.filterAttrs (_: value: builtins.length value > 1)
      (lib.mapAttrs
        (_: value: lib.unique value)
        (lib.mapAttrs
          (_: node: node.paths)
          nodes));
in
{
  inherit nodes groups duplicates;
}
