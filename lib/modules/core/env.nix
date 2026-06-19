{ config, ... }:
let
  user = config.devcontainer.user;
in
{
  config.devcontainer = {
    env.container = {
      XDG_CONFIG_HOME = "$HOME/.config";
      XDG_CACHE_HOME = "$HOME/.cache";
      XDG_DATA_HOME = "$HOME/.local/share";
      XDG_STATE_HOME = "$HOME/.local/state";
      XDG_RUNTIME_DIR = "/run/user/${toString user.uid}";
      PAGER = "less";
      EDITOR = "vim";
      VISUAL = "vim";
      NIX_CONFIG = "experimental-features = nix-command flakes";
      WORKSPACE = "/workspaces/$DEVCONTAINER_WORKSPACE";
    };
    env.origins.container = {
      XDG_CONFIG_HOME = [ "core.env" ];
      XDG_CACHE_HOME = [ "core.env" ];
      XDG_DATA_HOME = [ "core.env" ];
      XDG_STATE_HOME = [ "core.env" ];
      XDG_RUNTIME_DIR = [ "core.env" ];
      PAGER = [ "core.env" ];
      EDITOR = [ "core.env" ];
      VISUAL = [ "core.env" ];
      NIX_CONFIG = [ "core.env" ];
      WORKSPACE = [ "core.env" ];
    };
  };
}
