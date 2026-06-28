{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  nixSettingValueType =
    with types;
    oneOf [
      str
      int
      bool
      (listOf str)
    ];
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
  devpkgCoreChecks = [
    "devpkg list >/dev/null"
  ]
  ++ lib.optionals (config.programs.bash.enable && config.programs.bash.completion.enable) [
    "complete -p devpkg >/dev/null"
    "COMP_WORDS=(devpkg ad)"
    "COMP_CWORD=1"
    "_devpkg"
    ''printf '%s\n' "''${COMPREPLY[@]}" | grep -Fx add >/dev/null''
  ];
in
{
  options.nix = {
    package = mkOption {
      type = types.package;
      default = pkgs.nix;
    };
    settings = mkOption {
      type = types.attrsOf nixSettingValueType;
      default = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
      };
    };
    extraOptions = mkOption {
      type = types.lines;
      default = "";
    };
  };

  config = {
    environment.etc."nix/nix.conf".text = nixConfText;

    devcontainer.tests.cases."devpkg.core" = {
      tags = [
        "smoke"
        "baseline"
        "e2e-baseline"
        "devpkg"
      ];
      command = [
        "bash"
        (if config.programs.bash.enable && config.programs.bash.completion.enable then "-ic" else "-lc")
        (lib.concatStringsSep " && " devpkgCoreChecks)
      ];
    };
  };
}
