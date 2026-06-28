{
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.programs.nix-index = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    package = mkOption {
      type = types.package;
      default = pkgs.nix-index-with-db;
    };
    comma.enable = mkOption {
      type = types.bool;
      default = true;
    };
    comma.package = mkOption {
      type = types.nullOr types.package;
      default = if builtins.hasAttr "comma-with-db" pkgs then pkgs.comma-with-db else null;
    };
  };
}
