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

    devcontainer.tests.smoke = [
      {
        name = "nix-conf";
        command = [
          "bash"
          "-lc"
          "test -r /etc/nix/nix.conf && grep -F 'experimental-features = nix-command flakes' /etc/nix/nix.conf >/dev/null"
        ];
      }
      {
        name = "devpkg-list";
        command = [
          "bash"
          "-lc"
          "devpkg list >/dev/null"
        ];
      }
      {
        name = "devpkg-completion";
        command = [
          "bash"
          "-lc"
          "test -r /share/bash-completion/completions/devpkg && . /share/bash-completion/completions/devpkg && complete -p devpkg >/dev/null && devpkg complete packages div | grep -Fx dive >/dev/null"
        ];
      }
    ];
  };
}
