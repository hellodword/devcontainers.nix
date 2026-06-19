{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.compat.fhsRuntime;
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
      nix-ld
    ]
    ++ lib.optionals cfg.caCertificates [ pkgs.dockerTools.caCertificates ];
in
{
  config = lib.mkIf cfg.enable {
    devcontainer.packages = packages;

    devcontainer.graph.nodes."runtime/fhs-vscode" = {
      kind = "runtime";
      group = "01-fhs-vscode-runtime";
      paths = packages;
      stability = "stable";
      sharing = "global";
      priority = 96;
      securityClass = "trusted";
    };

    devcontainer.tests.smoke = [
      {
        name = "fhs-bash";
        command = [
          "bash"
          "-lc"
          "test -x /bin/bash && test -x /bin/sh && test -x /usr/bin/env"
        ];
      }
      {
        name = "fhs-os-release";
        command = [
          "bash"
          "-lc"
          "test -e /etc/os-release"
        ];
      }
      {
        name = "fhs-core-tools";
        command = [
          "bash"
          "-lc"
          "tar --version && (curl --version || wget --version)"
        ];
      }
    ]
    ++ lib.optionals cfg.caCertificates [
      {
        name = "fhs-ca-certificates";
        command = [
          "bash"
          "-lc"
          ''
            test -r "''${SSL_CERT_FILE:-}"
            test "''${NIX_SSL_CERT_FILE:-}" = "$SSL_CERT_FILE"
            curl --fail --silent --show-error --max-time 20 https://google.com >/dev/null
          ''
        ];
      }
    ]
    ++ [
      {
        name = "fhs-nix-ld";
        command = [
          "bash"
          "-lc"
          ''
            test -x /lib64/ld-linux-x86-64.so.2
            test -n "''${NIX_LD:-}"
            test -n "''${NIX_LD_LIBRARY_PATH:-}"
            env -i NIX_LD="$NIX_LD" NIX_LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH" PATH=/bin:/usr/bin \
              /lib64/ld-linux-x86-64.so.2 /usr/bin/env true
          ''
        ];
      }
    ];
  };
}
