{ ... }:
{
  config.devcontainer = {
    env.container = {
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

    path.segments = {
      project = [
        "$WORKSPACE/.devcontainer/bin"
        "$WORKSPACE/node_modules/.bin"
        "$WORKSPACE/.venv/bin"
      ];
      user = [
        "$XDG_DATA_HOME/devcontainer/bin"
        "$XDG_DATA_HOME/nix-profile/bin"
        "$HOME/.nix-profile/bin"
      ];
      language = [ ];
      system = [
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
      ];
    };

    path.order = [
      "project"
      "user"
      "language"
      "system"
    ];
  };
}
