{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.devcontainer.compat.fhsRuntime;
  nixLd = config.programs.nix-ld;
  pki = config.security.pki;
  packages =
    with pkgs;
    [
      bashInteractive
      coreutils
      gnutar
      gzip
      gnused
      gnugrep
      curl
      wget
      git
      glibc
      stdenv.cc.cc.lib
    ]
    ++ lib.optionals nixLd.enable [ nixLd.package ]
    ++ lib.optionals pki.installCACerts [ pki.package ];
in
{
  options = {
    programs.nix-ld = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      package = mkOption {
        type = types.package;
        default = pkgs.nix-ld;
      };
      libraries = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
      dynamicLoader = {
        x86_64.path = mkOption {
          type = types.str;
          default = "/lib64/ld-linux-x86-64.so.2";
        };
        aarch64.path = mkOption {
          type = types.str;
          default = "/lib/ld-linux-aarch64.so.1";
        };
      };
    };

    devcontainer.compat.fhsRuntime = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      binSh = mkOption {
        type = types.bool;
        default = true;
      };
      binBash = mkOption {
        type = types.bool;
        default = true;
      };
      usrBinEnv = mkOption {
        type = types.bool;
        default = true;
      };
      usrBinCoreTools = mkOption {
        type = types.bool;
        default = true;
      };
      etcOsRelease = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  config = lib.mkMerge [
    {
      devcontainer.layers.bucketDefinitions."fhs-vscode-runtime" = {
        order = 100;
        owner = "core/fhs-runtime";
        purpose = "FHS compatibility tools and runtime symlinks needed by VS Code and native binaries.";
      };
    }

    (lib.mkIf cfg.enable {
      environment.systemPackages = packages;

      devcontainer.graph.nodes."runtime/fhs-vscode" = {
        kind = "runtime";
        group = "fhs-vscode-runtime";
        paths = packages;
        stability = "stable";
        sharing = "global";
        priority = 96;
        securityClass = "trusted";
      };

      devcontainer.tests.cases = {
        "fhs.runtime" = {
          tags = [
            "smoke"
            "baseline"
            "e2e-baseline"
            "fhs"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                test -x /bin/bash
                test -x /bin/sh
                test -x /usr/bin/env
                test -e /etc/os-release
                tar --version
                (curl --version || wget --version)
              '';
            }
          ];
        };
      }
      // lib.optionalAttrs pki.installCACerts {
        "fhs.ca-certificates" = {
          tags = [
            "smoke"
            "baseline"
            "fhs"
            "ca-certificates"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                bundle=/etc/ssl/certs/ca-certificates.crt
                for env_name in SSL_CERT_FILE NIX_SSL_CERT_FILE CURL_CA_BUNDLE GIT_SSL_CAINFO; do
                  test "''${!env_name:-}" = "$bundle"
                done
                test -r "''${SSL_CERT_FILE:-}"
                test -s "$bundle"
                grep -q "BEGIN CERTIFICATE" "$bundle"
                grep -q "END CERTIFICATE" "$bundle"
              '';
            }
          ];
          timeoutSeconds = 45;
        };
      }
      // lib.optionalAttrs nixLd.enable {
        "fhs.nix-ld" = {
          tags = [
            "smoke"
            "baseline"
            "e2e-baseline"
            "fhs"
            "nix-ld"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                test -x /lib64/ld-linux-x86-64.so.2
                test -n "''${NIX_LD:-}"
                test -n "''${NIX_LD_LIBRARY_PATH:-}"
                env -i NIX_LD="$NIX_LD" NIX_LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH" PATH=/usr/bin \
                  /lib64/ld-linux-x86-64.so.2 /usr/bin/env true
              '';
            }
          ];
        };
      };
    })
  ];
}
