{ ... }:
{
  config.devcontainer.path = {
    segments = {
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

    order = [
      "project"
      "user"
      "language"
      "system"
    ];

    segmentOrigins = {
      project = {
        "$WORKSPACE/.devcontainer/bin" = [ "core.path.project" ];
        "$WORKSPACE/node_modules/.bin" = [ "core.path.project" ];
        "$WORKSPACE/.venv/bin" = [ "core.path.project" ];
      };
      user = {
        "$XDG_DATA_HOME/devcontainer/bin" = [ "core.path.user" ];
        "$XDG_DATA_HOME/nix-profile/bin" = [ "core.path.user" ];
        "$HOME/.nix-profile/bin" = [ "core.path.user" ];
      };
      system = {
        "/usr/local/bin" = [ "core.path.system" ];
        "/usr/bin" = [ "core.path.system" ];
        "/bin" = [ "core.path.system" ];
      };
    };
  };
}
