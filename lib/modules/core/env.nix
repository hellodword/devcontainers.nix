{ ... }:
{
  config.devcontainer.env.container = {
    XDG_CONFIG_HOME = "$HOME/.config";
    XDG_CACHE_HOME = "$HOME/.cache";
    XDG_DATA_HOME = "$HOME/.local/share";
    XDG_STATE_HOME = "$HOME/.local/state";
    XDG_RUNTIME_DIR = "/run/user/$UID";
    PAGER = "less";
    EDITOR = "vim";
    VISUAL = "vim";
    NIX_CONFIG = "experimental-features = nix-command flakes";
    WORKSPACE = "/workspaces/$DEVCONTAINER_WORKSPACE";
  };
}
