{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.programs.bash;
  locale = config.i18n;
  user = config.devcontainer.user;
  defaultAliases = {
    l = "ls -CF";
    la = "ls -A";
    ll = "ls -alF";
    ls = "ls --color=auto";
    grep = "grep --color=auto";
    "sha3-224sum" = "openssl dgst -sha3-224";
    "sha3-256sum" = "openssl dgst -sha3-256";
    "sha3-384sum" = "openssl dgst -sha3-384";
    "sha3-512sum" = "openssl dgst -sha3-512";
  };
  defaultAliasOrigins = lib.mapAttrs (_: _: [ "core.shell" ]) defaultAliases;
  invalidLocaleSettingNames = builtins.filter (
    name: name == "LC_ALL" || builtins.match "LC_[A-Z_]+" name == null
  ) (builtins.attrNames locale.extraLocaleSettings);
  validatedLocaleSettings =
    if invalidLocaleSettingNames != [ ] then
      throw (
        "i18n.extraLocaleSettings keys must be LC_* variables other than LC_ALL; invalid keys: "
        + lib.concatStringsSep ", " invalidLocaleSettingNames
      )
    else
      locale.extraLocaleSettings;
  localeArchivePath = "${locale.glibcLocales}/lib/locale/locale-archive";
  localeEnv = {
    LANG = locale.defaultLocale;
    LANGUAGE = locale.language;
    XDG_CONFIG_DIRS = "/etc/xdg";
    XDG_DATA_DIRS = "/usr/local/share:/usr/share";
    LOCALE_ARCHIVE = localeArchivePath;
  }
  // validatedLocaleSettings;
  shellRuntimePaths = [
    locale.glibcLocales
  ]
  ++ lib.optionals (cfg.enable && cfg.completion.enable) [ pkgs.bash-completion ];
  shellLocaleCommand = lib.concatStringsSep " && " [
    ''test "$LANG" = ${lib.escapeShellArg config.i18n.defaultLocale}''
    ''test "$LANGUAGE" = ${lib.escapeShellArg config.i18n.language}''
    ''test -r "$LOCALE_ARCHIVE"''
    "test -e /etc/localtime"
    "test -d /etc/zoneinfo"
    ''test "$TZDIR" = /etc/zoneinfo''
  ];
  shellInteractiveChecks = [
    "alias ll >/dev/null"
    "alias sha3-256sum >/dev/null"
  ]
  ++ lib.optionals config.programs.bash.completion.enable [
    "test -r /usr/share/bash-completion/bash_completion"
    "complete -p -D >/dev/null"
  ]
  ++ lib.optionals config.programs.bash.commandNotFound.enable [
    "type command_not_found_handle >/dev/null"
  ];
in
{
  options = {
    i18n = {
      defaultLocale = mkOption {
        type = types.str;
        default = "en_US.UTF-8";
      };
      extraLocaleSettings = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      glibcLocales = mkOption {
        type = types.package;
        default = pkgs.glibcLocales;
      };
      supportedLocales = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      language = mkOption {
        type = types.str;
        default = "en_US:en";
      };
    };

    programs.bash = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      prompt.enable = mkOption {
        type = types.bool;
        default = true;
      };
      history.enable = mkOption {
        type = types.bool;
        default = true;
      };
      completion.enable = mkOption {
        type = types.bool;
        default = true;
      };
      commandNotFound.enable = mkOption {
        type = types.bool;
        default = config.programs.nix-index.enable;
      };
    };

    environment = {
      shellAliases = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      shellAliasOrigins = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
      shellInit = mkOption {
        type = types.lines;
        default = "";
      };
      interactiveShellInit = mkOption {
        type = types.lines;
        default = "";
      };
    };
  };

  config = lib.mkMerge [
    {
      devcontainer.layers.bucketDefinitions."shell-runtime" = {
        order = 11300;
        owner = "core/shell";
        purpose = "Locale and interactive shell runtime support.";
      };

      environment.shellAliases = lib.mapAttrs (_: value: lib.mkDefault value) defaultAliases;
      environment.shellAliasOrigins = lib.mapAttrs (_: value: lib.mkDefault value) defaultAliasOrigins;

      environment.variables = localeEnv;
      environment.variableOrigins = lib.mapAttrs (_: _: [ "core.locale" ]) localeEnv;

      devcontainer.filesystem.directories = {
        "${user.home}/.config" = {
          mode = "0755";
          uid = user.uid;
          gid = user.gid;
        };
        "${user.home}/.cache" = {
          mode = "0755";
          uid = user.uid;
          gid = user.gid;
        };
        "${user.home}/.local" = {
          mode = "0755";
          uid = user.uid;
          gid = user.gid;
        };
        "${user.home}/.local/share" = {
          mode = "0755";
          uid = user.uid;
          gid = user.gid;
        };
        "${user.home}/.local/state" = {
          mode = "0755";
          uid = user.uid;
          gid = user.gid;
        };
        "${user.home}/.local/state/bash" = {
          mode = "0700";
          uid = user.uid;
          gid = user.gid;
        };
      };
    }

    (lib.mkIf (shellRuntimePaths != [ ]) {
      devcontainer.graph.nodes."runtime/shell" = {
        kind = "runtime";
        group = "shell-runtime";
        paths = shellRuntimePaths;
        stability = "very-stable";
        sharing = "global";
        priority = 96;
        securityClass = "trusted";
      };
    })

    {
      devcontainer.tests.cases."shell.locale" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "shell"
          "locale"
        ];
        command = [
          "bash"
          "-lc"
          shellLocaleCommand
        ];
      };
    }

    (lib.mkIf cfg.enable {
      devcontainer.tests.cases."shell.interactive" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "shell"
        ];
        command = [
          "bash"
          "-ic"
          (lib.concatStringsSep " && " shellInteractiveChecks)
        ];
      };
    })
  ];
}
