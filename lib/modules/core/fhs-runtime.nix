{
  lib,
  pkgs,
  config,
  ...
}:
let
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
  config = lib.mkIf cfg.enable {
    environment.systemPackages = packages;

    devcontainer.graph.nodes."runtime/fhs-vscode" = {
      kind = "runtime";
      group = "01-fhs-vscode-runtime";
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
        command = [
          "bash"
          "-lc"
          "test -x /bin/bash && test -x /bin/sh && test -x /usr/bin/env && test -e /etc/os-release && tar --version && (curl --version || wget --version)"
        ];
      };
    }
    // lib.optionalAttrs pki.installCACerts {
      "fhs.ca-certificates" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "fhs"
          "ca-certificates"
        ];
        command = [
          "bash"
          "-lc"
          ''
            test -r "''${SSL_CERT_FILE:-}"
            test "''${NIX_SSL_CERT_FILE:-}" = "$SSL_CERT_FILE"
            curl --fail --silent --show-error --max-time 20 https://google.com >/dev/null
          ''
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
        command = [
          "bash"
          "-lc"
          ''
            test -x /lib64/ld-linux-x86-64.so.2
            test -n "''${NIX_LD:-}"
            test -n "''${NIX_LD_LIBRARY_PATH:-}"
            env -i NIX_LD="$NIX_LD" NIX_LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH" PATH=/usr/bin \
              /lib64/ld-linux-x86-64.so.2 /usr/bin/env true
          ''
        ];
      };
    };
  };
}
