{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  user = config.devcontainer.user;
in
{
  options.devcontainer.filesystem = {
    osRelease = {
      name = mkOption {
        type = types.str;
        default = "devcontainer-nix";
      };
      id = mkOption {
        type = types.str;
        default = "devcontainer-nix";
      };
      versionId = mkOption {
        type = types.str;
        default = "26.05";
      };
      prettyName = mkOption {
        type = types.str;
        default = "Devcontainer Nix 26.05";
      };
    };
    directories = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            mode = mkOption { type = types.str; };
            uid = mkOption { type = types.int; };
            gid = mkOption { type = types.int; };
          };
        }
      );
      default = { };
    };
  };

  config.devcontainer = {
    filesystem.directories = {
      "/home" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      ${user.home} = {
        mode = "0755";
        uid = user.uid;
        gid = user.gid;
      };
      "${user.home}/.codex" = {
        mode = "0755";
        uid = user.uid;
        gid = user.gid;
      };
      "/tmp" = {
        mode = "1777";
        uid = 0;
        gid = 0;
      };
      "/etc/xdg" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      "/var" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      "/var/cache" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      "/var/lib" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      "/var/log" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      "/var/tmp" = {
        mode = "1777";
        uid = 0;
        gid = 0;
      };
      "/run" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      "/run/user" = {
        mode = "0755";
        uid = 0;
        gid = 0;
      };
      "/run/user/${toString user.uid}" = {
        mode = "0700";
        uid = user.uid;
        gid = user.gid;
      };
      "/workspaces" = {
        mode = "0777";
        uid = 0;
        gid = 0;
      };
    };

    tests.cases = {
      "base.user" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "base"
          "user"
        ];
        scripts = [
          {
            shell = "bash";
            interactive = false;
            command = ''
              set -e
              test "$(id -un)" = vscode
              test "$(id -u)" = 1000
              test "$(id -gn)" = vscode
              test "$(id -g)" = 1000
              test "$HOME" = /home/vscode
            '';
          }
        ];
      };
      "base.filesystem" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "base"
          "filesystem"
        ];
        scripts = [
          {
            shell = "bash";
            interactive = false;
            command = ''
              set -e
              test -w /tmp
              test -w /var/tmp
              test -w /workspaces
              test "$XDG_RUNTIME_DIR" = /run/user/1000
              test -d "$XDG_RUNTIME_DIR"
            '';
          }
        ];
      };
      "base.nix-store" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "base"
          "nix"
        ];
        scripts = [
          {
            shell = "bash";
            interactive = false;
            command = ''
              set -e
              test -d /nix/var/nix
              test -w /nix/store
              test -w /nix/var/nix/db
            '';
          }
        ];
      };
    };
  };
}
