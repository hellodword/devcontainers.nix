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
  config.devcontainer.layers.bucketDefinitions."20-c-env" = {
    order = 17;
    owner = "runtimes/c-env";
    purpose = "Shared C/C++ build toolchain used by native language profiles.";
  };

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
