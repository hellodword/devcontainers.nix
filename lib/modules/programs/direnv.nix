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
  config = lib.mkMerge [
    {
      devcontainer.profiles."program/direnv" = {
        kind = "program";
        group = "07-workflow-format-tools";
        packages = packages;
        priority = 82;
        stability = "stable";
        sharing = "global";
        securityClass = "trusted";
        provides.commands = [
          "direnv"
          "nix-direnv"
        ];
        env.variables.DIRENV_CONFIG = "/etc/direnv";
        tests.smoke = [
          {
            name = "direnv-hook";
            command = [
              "bash"
              "-ic"
              "command -v direnv >/dev/null && type _direnv_hook >/dev/null"
            ];
          }
        ];
      };
    }

    (lib.mkIf config.devcontainer.profiles."program/direnv".enable {
      programs.direnv.enable = lib.mkDefault true;
    })

    (lib.mkIf cfg.enable {
      environment.interactiveShellInit = hook;
      environment.etc."direnv/direnvrc".text = direnvrc;
    })
  ];
}
