{ lib, ... }:
let
  inherit (lib) mkOption types;
  moduleTypes = import ../types.nix { inherit lib; };
  inherit (moduleTypes) lifecycleTaskType;
in
{
  options.devcontainer.lifecycle.tasks = mkOption {
    type = types.attrsOf lifecycleTaskType;
    default = { };
  };

  config.devcontainer = {
    layers.bucketDefinitions."90-lifecycle-runtime" = {
      order = 36;
      owner = "core/lifecycle";
      purpose = "Lifecycle helper tasks and task metadata runtime.";
    };

    lifecycle.tasks = {
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
  };
}
