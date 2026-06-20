{ lib, ... }:
{
  config = {
    devcontainer.image = {
      name = lib.mkOverride 1000 "nix";
      tags = lib.mkDefault [ "latest" ];
    };

    devcontainer.profiles = {
      "runtime/base".enable = lib.mkDefault true;
      "toolset/foundation".enable = lib.mkDefault true;
      "toolset/source-control".enable = lib.mkDefault true;
      "toolset/fetch-archive".enable = lib.mkDefault true;
      "toolset/search-navigation".enable = lib.mkDefault true;
      "toolset/inspect-debug".enable = lib.mkDefault true;
      "toolset/workflow-format".enable = lib.mkDefault true;
      "program/direnv".enable = lib.mkDefault true;
      "toolset/editor-support".enable = lib.mkDefault true;
      "toolset/docker-client".enable = lib.mkDefault true;
      "toolset/nix-index".enable = lib.mkDefault true;
      "toolset/agents".enable = lib.mkDefault true;
      "editor/base".enable = lib.mkDefault true;
      "runtime/nix".enable = lib.mkDefault true;
      "language/nix".enable = lib.mkDefault true;
    };
  };
}
