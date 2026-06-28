{
  self,
  pkgs,
  lib,
  system,
  inputs,
}:
{ modules }:
let
  moduleRegistry = import ../modules { inherit lib; };
in
lib.evalModules {
  specialArgs = {
    inherit
      self
      pkgs
      system
      inputs
      ;
  };

  modules = moduleRegistry.allModules ++ modules;
}
