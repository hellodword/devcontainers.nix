{
  pkgs,
  lib,
  nixpkgs,
  compiler,
  ...
}:

let
  fixtures = import ./fixtures.nix {
    inherit
      pkgs
      lib
      nixpkgs
      compiler
      ;
  };
  inherit (fixtures)
    graphDuplicateLeftPath
    graphDuplicateRepeatedPath
    graphDuplicateReport
    graphDuplicateRightPath
    graphDuplicateSharedPath
    ;
in
{
  contracts-compiler-graph =
    assert builtins.attrNames graphDuplicateReport == [ graphDuplicateSharedPath ];
    assert
      graphDuplicateReport.${graphDuplicateSharedPath} == [
        "duplicate/first"
        "duplicate/second"
      ];
    assert !(builtins.hasAttr graphDuplicateRepeatedPath graphDuplicateReport);
    assert !(builtins.hasAttr graphDuplicateLeftPath graphDuplicateReport);
    assert !(builtins.hasAttr graphDuplicateRightPath graphDuplicateReport);
    pkgs.writeText "contracts-compiler-graph.json" (builtins.toJSON graphDuplicateReport);
}
