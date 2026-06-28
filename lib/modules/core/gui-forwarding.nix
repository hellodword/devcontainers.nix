{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.devcontainer.gui.forwarding;
in
{
  options.devcontainer.gui.forwarding.enable = mkOption {
    type = types.bool;
    default = true;
  };

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
