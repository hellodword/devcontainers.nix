{
  pkgs,
  ...
}:
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
  config.devcontainer.profiles."runtime/c-env" = {
    kind = "runtime";
    group = "20-c-env";
    packages = packages;
    priority = 86;
    stability = "stable";
    sharing = "cross-language";
    securityClass = "trusted";
    provides.commands = [
      "cc"
      "gcc"
      "pkg-config"
      "cmake"
      "ninja"
      "meson"
      "muon"
      "make"
      "autoconf"
      "automake"
      "libtool"
    ];
  };
}
