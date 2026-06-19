{ lib, pkgs, config, ... }:
let
  packages = with pkgs; [
    gcc
    binutils
    pkg-config
    cmake
    ninja
    meson
    muon
    gnumake
    autoconf
    automake
    libtool
  ];
in
{
  config = lib.mkIf config.devcontainer.runtimes.cEnv.enable {
    devcontainer.packages = packages;
    devcontainer.graph.nodes."runtime/c-env" = {
      kind = "runtime";
      group = "20-c-env";
      paths = packages;
      stability = "stable";
      sharing = "cross-language";
      priority = 86;
      securityClass = "trusted";
    };
  };
}
