{
  self,
  pkgs,
  lib,
  nixpkgs,
  compiler,
  images,
  workflows,
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
      workflows
      ;
  };
in
(import ./checks/contracts.nix commonArgs)
// (import ./checks/artifacts.nix commonArgs)
// (import ./checks/tooling.nix commonArgs)
// (import ./checks/report-cli.nix commonArgs)
// (import ./checks/workflows.nix commonArgs)
