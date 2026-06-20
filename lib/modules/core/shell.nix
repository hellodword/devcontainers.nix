{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.shell;
  locale = config.devcontainer.locale;
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
  localeArchivePath = "${locale.archive.package}/lib/locale/locale-archive";
  localeEnv = lib.optionalAttrs locale.enable (
    {
      LANG = locale.lang;
      LANGUAGE = locale.language;
      XDG_CONFIG_DIRS = "/etc/xdg";
      XDG_DATA_DIRS = "/usr/local/share:/usr/share:/share";
    }
    // locale.lc
    // lib.optionalAttrs (locale.lcAll != null) {
      LC_ALL = locale.lcAll;
    }
    // lib.optionalAttrs locale.archive.enable {
      LOCALE_ARCHIVE = localeArchivePath;
    }
  );
  shellRuntimePaths =
    lib.optionals (locale.enable && locale.archive.enable) [ locale.archive.package ]
    ++ lib.optionals (cfg.enable && cfg.bash.completion.enable) [ pkgs.bash-completion ];
in
{
  config.devcontainer = lib.mkMerge [
    {
      shell.aliases = lib.mapAttrs (_: value: lib.mkDefault value) defaultAliases;
      shell.aliasOrigins = lib.mapAttrs (_: value: lib.mkDefault value) defaultAliasOrigins;

      env.container = localeEnv;
      env.origins.container = lib.mapAttrs (_: _: [ "core.locale" ]) localeEnv;

      filesystem.directories = {
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
      graph.nodes."runtime/shell" = {
        kind = "runtime";
        group = "14-shell-runtime";
        paths = shellRuntimePaths;
        stability = "very-stable";
        sharing = "global";
        priority = 96;
        securityClass = "trusted";
      };
    })

    (lib.mkIf locale.enable {
      tests.smoke = [
        {
          name = "locale-env";
          command = [
            "bash"
            "-lc"
            (
              ''test "$LANG" = ${lib.escapeShellArg locale.lang} && test "$LANGUAGE" = ${lib.escapeShellArg locale.language}''
              + lib.optionalString locale.archive.enable " && test -r \"$LOCALE_ARCHIVE\""
            )
          ];
        }
      ];
    })

    (lib.mkIf cfg.enable {
      tests.smoke = [
        {
          name = "bash-interactive";
          command = [
            "bash"
            "-ic"
            (
              "alias ll >/dev/null && alias sha3-256sum >/dev/null"
              + lib.optionalString cfg.bash.commandNotFound.enable " && type command_not_found_handle >/dev/null"
            )
          ];
        }
      ];
    })

    (lib.mkIf (cfg.enable && cfg.bash.completion.enable) {
      tests.smoke = [
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
