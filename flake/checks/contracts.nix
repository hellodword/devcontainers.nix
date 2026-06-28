{
  pkgs,
  lib,
  compiler,
  images,
  targets,
  ...
}:

let
  commonArgs = {
    inherit
      pkgs
      lib
      compiler
      images
      targets
      ;
  };
in
(import ./contracts/reports.nix commonArgs)
// (import ./contracts/targets.nix commonArgs)
// (import ./contracts/runtime-helpers.nix commonArgs)
// (import ./contracts/compiler.nix commonArgs)
