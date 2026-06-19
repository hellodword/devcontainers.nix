{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.compat.fhsRuntime;
  packages = with pkgs; [
    bashInteractive
    coreutils
    gnutar
    gzip
    gnused
    gnugrep
    curl
    wget
    git
    cacert
    glibc
    stdenv.cc.cc.lib
    nix-ld
  ];
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
    ];
  };
}
