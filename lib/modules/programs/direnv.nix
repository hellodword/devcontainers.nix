{ lib, config, ... }:
let
  cfg = config.programs.direnv;
  packages = [ cfg.package ] ++ lib.optional cfg.nix-direnv.enable cfg.nix-direnv.package;
  direnvrc = lib.optionalString cfg.nix-direnv.enable ''
    source ${cfg.nix-direnv.package}/share/nix-direnv/direnvrc
  '';
  hook = ''
    if command -v direnv >/dev/null 2>&1; then
      eval "$(direnv hook bash)"
    fi
  '';
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = packages;
        environment.variables.DIRENV_CONFIG = "/etc/direnv";
        environment.variableOrigins.DIRENV_CONFIG = [ "programs.direnv" ];
        environment.interactiveShellInit = hook;
        environment.etc."direnv/direnvrc".text = direnvrc;

        devcontainer.graph.nodes."program/direnv" = {
          kind = "program";
          group = "07-workflow-format-tools";
          paths = packages;
          stability = "stable";
          sharing = "global";
          priority = 82;
          securityClass = "trusted";
        };
      }

      {
        devcontainer.tests.smoke = [
          {
            name = "direnv-hook";
            command = [
              "bash"
              "-ic"
              "command -v direnv >/dev/null && type _direnv_hook >/dev/null"
            ];
          }
        ];
      }
    ]
  );
}
