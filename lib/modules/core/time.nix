{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.time;
in
{
  options.time.timeZone = mkOption {
    type = types.nullOr types.str;
    default = "Etc/UTC";
  };

  config = lib.mkIf (cfg.timeZone != null) {
    environment.etc."zoneinfo" = {
      source = "${pkgs.tzdata}/share/zoneinfo";
      mode = "0755";
    };
    environment.etc."localtime".source = "${pkgs.tzdata}/share/zoneinfo/${cfg.timeZone}";
    environment.variables.TZDIR = "/etc/zoneinfo";
    environment.variableOrigins.TZDIR = [ "core.time" ];
  };
}
