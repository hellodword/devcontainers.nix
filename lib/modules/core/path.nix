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
  };
}
