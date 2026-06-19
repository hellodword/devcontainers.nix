{ ... }:
{
  config.devcontainer.lifecycle.tasks = {
    "xdg-dirs" = {
      phase = "postCreate";
      once = true;
      user = "vscode";
      command = [
        "devcontainer-task-runner"
        "ensure-xdg"
      ];
      timeoutSeconds = 10;
    };

    "vscode-extension-projection" = {
      phase = "postCreate";
      once = true;
      user = "vscode";
      command = [
        "vscode-extension-projector"
        "activate"
        "--index"
        "/usr/share/devcontainer/vscode/extensions-index.json"
      ];
      timeoutSeconds = 120;
      needs = [ "xdg-dirs" ];
    };
  };
}
