{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  envValueType =
    with types;
    oneOf [
      str
      int
      bool
      path
      package
      (listOf str)
    ];
  etcEntryType = types.submodule (
    { name, ... }:
    {
      options = {
        target = mkOption {
          type = types.str;
          default = name;
        };
        text = mkOption {
          type = types.nullOr types.lines;
          default = null;
        };
        source = mkOption {
          type = types.nullOr (
            types.oneOf [
              types.str
              types.path
              types.package
            ]
          );
          default = null;
        };
        mode = mkOption {
          type = types.str;
          default = "0644";
        };
        uid = mkOption {
          type = types.int;
          default = 0;
        };
        gid = mkOption {
          type = types.int;
          default = 0;
        };
      };
    }
  );
  user = config.devcontainer.user;
in
{
  options = {
    environment = {
      systemPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
      pathsToLink = mkOption {
        type = types.listOf types.str;
        default = [
          "/bin"
          "/include"
          "/lib"
          "/lib64"
          "/libexec"
          "/share"
          "/etc"
        ];
      };
      extraOutputsToInstall = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      etc = mkOption {
        type = types.attrsOf etcEntryType;
        default = { };
      };
      variables = mkOption {
        type = types.attrsOf envValueType;
        default = { };
      };
      variableOrigins = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
    };

    devcontainer = {
      remoteEnv = mkOption {
        type = types.attrsOf envValueType;
        default = { };
      };
      remoteEnvOrigins = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
    };
  };

  config = {
    environment.variables = {
      XDG_CONFIG_HOME = "$HOME/.config";
      XDG_CACHE_HOME = "$HOME/.cache";
      XDG_DATA_HOME = "$HOME/.local/share";
      XDG_STATE_HOME = "$HOME/.local/state";
      XDG_RUNTIME_DIR = "/run/user/${toString user.uid}";
      PAGER = "less";
      EDITOR = "vim";
      VISUAL = "vim";
      NIXPKGS_CONFIG = "/etc/nixpkgs/config.nix";
      NIXPKGS_ALLOW_UNFREE = "1";
      NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM = "1";
      NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE = "1";
      DO_NOT_TRACK = "true";
      NIX_PAGER = "cat";
      NIX_PATH = "nixpkgs=/usr/share/devcontainer/nixpkgs";
      DEVCONTAINER_FLAKE_INPUTS = "/usr/share/devcontainer/flake-inputs.json";
      DEVPKG_NIXPKGS_REF = "path:${inputs.nixpkgs.outPath}";
      WORKSPACE = "/workspaces/$DEVCONTAINER_WORKSPACE";
    };
    environment.variableOrigins = {
      XDG_CONFIG_HOME = [ "core.env" ];
      XDG_CACHE_HOME = [ "core.env" ];
      XDG_DATA_HOME = [ "core.env" ];
      XDG_STATE_HOME = [ "core.env" ];
      XDG_RUNTIME_DIR = [ "core.env" ];
      PAGER = [ "core.env" ];
      EDITOR = [ "core.env" ];
      VISUAL = [ "core.env" ];
      NIXPKGS_CONFIG = [ "core.env" ];
      NIXPKGS_ALLOW_UNFREE = [ "core.env" ];
      NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM = [ "core.env" ];
      NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE = [ "core.env" ];
      DO_NOT_TRACK = [ "core.env" ];
      NIX_PAGER = [ "core.env" ];
      NIX_PATH = [ "core.env" ];
      DEVCONTAINER_FLAKE_INPUTS = [ "core.env" ];
      DEVPKG_NIXPKGS_REF = [ "core.env" ];
      WORKSPACE = [ "core.env" ];
    };

    devcontainer.tests.cases."nixpkgs.config" = {
      tags = [
        "smoke"
        "baseline"
        "nix"
        "config"
      ];
      scripts = [
        {
          shell = "bash";
          interactive = false;
          command = ''
            set -e
            test "$NIXPKGS_CONFIG" = /etc/nixpkgs/config.nix
            test -r "$NIXPKGS_CONFIG"
            test "$NIXPKGS_ALLOW_UNFREE" = 1
            test "$NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM" = 1
            test "$NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE" = 1
            test "$DO_NOT_TRACK" = true
            test "$NIX_PAGER" = cat
            test "$NIX_PATH" = nixpkgs=/usr/share/devcontainer/nixpkgs
            test "$DEVCONTAINER_FLAKE_INPUTS" = /usr/share/devcontainer/flake-inputs.json
            test -r "$DEVCONTAINER_FLAKE_INPUTS"
            case "$DEVPKG_NIXPKGS_REF" in
              path:/nix/store/*-source) true ;;
              *) false ;;
            esac
          '';
        }
      ];
    };
  };
}
