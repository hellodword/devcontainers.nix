{
  self,
  pkgs,
  lib,
  nixpkgs,
  compiler,
  images,
  targets,
}:

let
  commonArgs = {
    inherit
      self
      pkgs
      lib
      nixpkgs
      compiler
      images
      targets
      ;
  };
in
(import ./checks/contracts.nix commonArgs)
// (import ./checks/artifacts.nix commonArgs)
// (import ./checks/tooling.nix commonArgs)
// (import ./checks/report-cli.nix commonArgs)
