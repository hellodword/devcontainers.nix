{
  self,
  pkgs,
  lib,
  system,
  inputs,
  moduleRegistry,
}:
{ modules }:
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
