{
  self,
  pkgs,
  lib,
  system,
  inputs,
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

  modules = [
    ../modules/core/options.nix
    ../modules/core/base.nix
    ../modules/core/user.nix
    ../modules/core/filesystem.nix
    ../modules/core/env.nix
    ../modules/core/path.nix
    ../modules/core/graph.nix
    ../modules/core/fhs-runtime.nix
    ../modules/core/metadata.nix
    ../modules/core/lifecycle.nix
    ../modules/core/vscode-extensions.nix

    ../modules/toolsets/foundation.nix
    ../modules/toolsets/source-control.nix
    ../modules/toolsets/fetch-archive.nix
    ../modules/toolsets/search-navigation.nix
    ../modules/toolsets/inspect-debug.nix
    ../modules/toolsets/workflow-format.nix
    ../modules/toolsets/data-network.nix
    ../modules/toolsets/docker-client.nix
    ../modules/toolsets/agents.nix
    ../modules/toolsets/nix-index.nix

    ../modules/runtimes/c-env.nix
    ../modules/runtimes/python-runtime.nix
    ../modules/runtimes/nodejs-runtime.nix

    ../modules/languages/python.nix
    ../modules/languages/nodejs.nix
    ../modules/languages/go.nix
    ../modules/languages/rust.nix
    ../modules/languages/flutter.nix
  ]
  ++ modules;
}
