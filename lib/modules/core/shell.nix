{
  lib,
  pkgs,
  config,
  ...
}:
let
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
    XDG_DATA_DIRS = "/usr/local/share:/usr/share:/share";
    LOCALE_ARCHIVE = localeArchivePath;
  }
  // validatedLocaleSettings;
  shellRuntimePaths = [
    locale.glibcLocales
  ]
  ++ lib.optionals (cfg.enable && cfg.completion.enable) [ pkgs.bash-completion ];
in
{
  config = lib.mkMerge [
    {
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
        group = "14-shell-runtime";
        paths = shellRuntimePaths;
        stability = "very-stable";
        sharing = "global";
        priority = 96;
        securityClass = "trusted";
      };
    })

    {
      devcontainer.tests.smoke = [
        {
          name = "locale-env";
          command = [
            "bash"
            "-lc"
            (
              ''test "$LANG" = ${lib.escapeShellArg locale.defaultLocale} && test "$LANGUAGE" = ${lib.escapeShellArg locale.language}''
              + " && test -r \"$LOCALE_ARCHIVE\""
            )
          ];
        }
      ];
    }

    (lib.mkIf cfg.enable {
      devcontainer.tests.smoke = [
        {
          name = "bash-interactive";
          command = [
            "bash"
            "-ic"
            (
              "alias ll >/dev/null && alias sha3-256sum >/dev/null"
              + lib.optionalString cfg.commandNotFound.enable " && type command_not_found_handle >/dev/null"
            )
          ];
        }
      ];
    })

    (lib.mkIf (cfg.enable && cfg.completion.enable) {
      devcontainer.tests.smoke = [
        {
          name = "bash-completion";
          command = [
            "bash"
            "-ic"
            "type _init_completion >/dev/null || complete -p >/dev/null"
          ];
        }
      ];
    })
  ];
}
