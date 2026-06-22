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

    devcontainer.tests.capabilities =
      [ "fhs.runtime" ]
      ++ lib.optionals pki.installCACerts [ "fhs.ca-certificates" ]
      ++ lib.optionals nixLd.enable [ "fhs.nix-ld" ];
  };
}
