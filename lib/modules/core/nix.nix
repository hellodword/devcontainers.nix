{ lib, config, ... }:
let
  cfg = config.nix;
  renderValue =
    value:
    if builtins.isBool value then
      if value then "true" else "false"
    else if builtins.isList value then
      lib.concatStringsSep " " (map toString value)
    else
      toString value;
  settingsText = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "${name} = ${renderValue value}") cfg.settings
  );
  nixConfText = lib.concatStringsSep "\n" (
    builtins.filter (line: line != "") [
      settingsText
      cfg.extraOptions
      ""
    ]
  );
in
{
  config = {
    environment.etc."nix/nix.conf".text = nixConfText;

    devcontainer.tests.capabilities = [ "devpkg.core" ];
  };
}
