# C and build system toolchain plus compiler header closure and CGO/bindgen flags.
{ pkgs }:
let
  buildLibProfile = "/home/vscode/.local/share/devpkg/build-libraries/profile";
  usrPackages = with pkgs; [
    gcc
    binutils
    ccache
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
  storeOnly = [
    pkgs.glibc.dev
    pkgs.patchelf
    pkgs.stdenv.cc.cc
    pkgs.stdenv
    pkgs.stdenvNoCC
    pkgs.zlib.out
    pkgs.zlib.dev
  ];
  cacheEnv = {
    CCACHE_DIR = "/home/vscode/.cache/ccache";
    CCACHE_MAXSIZE = "20G";
  };
  devEnv = {
    NIX_CFLAGS_COMPILE = "-isystem ${buildLibProfile}/include";
    NIX_LDFLAGS = "-L${buildLibProfile}/lib -L${buildLibProfile}/lib64";
    CGO_CFLAGS = "-I${buildLibProfile}/include";
    CGO_LDFLAGS = "-L${buildLibProfile}/lib -L${buildLibProfile}/lib64";
    BINDGEN_EXTRA_CLANG_ARGS = "-isystem ${pkgs.glibc.dev}/include -isystem ${buildLibProfile}/include";
  };
in
{
  inherit usrPackages cacheEnv devEnv;
  storeDeps = usrPackages ++ storeOnly;
  pathSegments = [ ];
  env = cacheEnv // devEnv;
}
