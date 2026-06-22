{
  lib,
  config,
  ...
}:
let
  cfg = config.devcontainer.gui.forwarding;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      devcontainer.lifecycle.tasks."gui-env-refresh" = {
        phase = "postStart";
        once = false;
        user = "vscode";
        command = [
          "devcontainer-gui-env"
          "refresh"
        ];
        timeoutSeconds = 10;
      };

    })

    (lib.mkIf (!cfg.enable) {
      environment.variables.DEVCONTAINER_GUI_ENV = lib.mkDefault "0";
      environment.variableOrigins.DEVCONTAINER_GUI_ENV = [ "core.gui-forwarding" ];
    })
  ];
}
