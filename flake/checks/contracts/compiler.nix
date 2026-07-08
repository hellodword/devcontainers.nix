{
  pkgs,
  lib,
  nixpkgs,
  compiler,
  ...
}:

let
  compilerArgs = {
    inherit
      pkgs
      lib
      nixpkgs
      compiler
      ;
  };
in
lib.foldl' (acc: path: acc // (import path compilerArgs)) { } [
  ./compiler/env.nix
  ./compiler/fhs-options.nix
  ./compiler/graph.nix
  ./compiler/profiles.nix
  ./compiler/metadata-security.nix
]
