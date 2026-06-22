{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.time;
in
{
  config = lib.mkIf (cfg.timeZone != null) {
    environment.etc."zoneinfo" = {
      source = "${pkgs.tzdata}/share/zoneinfo";
      mode = "0755";
    };
    environment.etc."localtime".source = "${pkgs.tzdata}/share/zoneinfo/${cfg.timeZone}";
    environment.variables.TZDIR = "/etc/zoneinfo";
    environment.variableOrigins.TZDIR = [ "core.time" ];

    devcontainer.tests.capabilities = [ "shell.locale" ];
  };
}
