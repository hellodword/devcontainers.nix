{
  lib,
  config,
  ...
}:
let
  cfg = config.devcontainer.gui.forwarding;
  guiEnvFile = "/run/user/${toString config.devcontainer.user.uid}/devcontainer-gui-env.sh";
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

      devcontainer.tests.smoke = [
        {
          name = "gui-env-refresh";
          command = [
            "bash"
            "-lc"
            "DEVCONTAINER_GUI_ENV=0 devcontainer-gui-env refresh >/dev/null && . ${lib.escapeShellArg guiEnvFile} && test -z \"\${QT_QPA_PLATFORM:-}\" && test -z \"\${GDK_BACKEND:-}\" && test -z \"\${NIXOS_OZONE_WL:-}\""
          ];
        }
      ];
    })

    (lib.mkIf (!cfg.enable) {
      environment.variables.DEVCONTAINER_GUI_ENV = lib.mkDefault "0";
      environment.variableOrigins.DEVCONTAINER_GUI_ENV = [ "core.gui-forwarding" ];
    })
  ];
}
