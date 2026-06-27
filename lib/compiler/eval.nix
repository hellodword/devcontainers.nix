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
    ../modules/core/shell.nix
    ../modules/core/nix.nix
    ../modules/core/time.nix
    ../modules/core/security-pki.nix
    ../modules/core/fonts.nix
    ../modules/core/libraries.nix
    ../modules/core/path.nix
    ../modules/core/fhs-runtime.nix
    ../modules/core/metadata.nix
    ../modules/core/lifecycle.nix
    ../modules/core/gui-forwarding.nix
    ../modules/profiles/web-stacks.nix

    ../modules/editor/base.nix
    ../modules/editor/core.nix
    ../modules/editor/prettier.nix
    ../modules/editor/shellcheck.nix
    ../modules/editor/markdown-preview.nix

    ../modules/programs/git.nix
    ../modules/programs/ssh.nix
    ../modules/programs/nix-index.nix

    ../modules/toolsets/foundation.nix
    ../modules/toolsets/source-control.nix
    ../modules/toolsets/fetch-archive.nix
    ../modules/toolsets/search-navigation.nix
    ../modules/toolsets/inspect-debug.nix
    ../modules/toolsets/workflow-format.nix
    ../modules/toolsets/editor-support.nix
    ../modules/toolsets/data-network.nix
    ../modules/toolsets/docker-client.nix
    ../modules/toolsets/agents.nix
    ../modules/toolsets/nix-index.nix

    ../modules/tools/shell-format.nix
    ../modules/tools/editorconfig.nix

    ../modules/runtimes/base.nix
    ../modules/runtimes/c-env.nix
    ../modules/runtimes/python-runtime.nix
    ../modules/runtimes/nodejs-runtime.nix

    ../modules/languages/just.nix
    ../modules/languages/yaml.nix
    ../modules/languages/xml.nix
    ../modules/languages/toml.nix
    ../modules/languages/jinja.nix
    ../modules/languages/protobuf.nix
    ../modules/languages/nix.nix
    ../modules/languages/python.nix
    ../modules/languages/nodejs.nix
    ../modules/languages/go.nix
    ../modules/languages/rust.nix
    ../modules/languages/flutter.nix
  ]
  ++ modules;
}
