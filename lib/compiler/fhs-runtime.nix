{
  lib,
  pkgs,
  system,
}:
{ config }:
let
  cfg = config.devcontainer.compat.fhsRuntime;
  osRelease = config.devcontainer.filesystem.osRelease;
  osReleaseText = ''
    NAME="${osRelease.name}"
    ID=${osRelease.id}
    VERSION_ID="${osRelease.versionId}"
    PRETTY_NAME="${osRelease.prettyName}"
  '';
  currentDynamicLoader =
    if system == "x86_64-linux" then
      cfg.dynamicLoader.x86_64.path
    else if system == "aarch64-linux" then
      cfg.dynamicLoader.aarch64.path
    else
      null;
  dynamicLoaderFile =
    if system == "x86_64-linux" then
      "ld-linux-x86-64.so.2"
    else if system == "aarch64-linux" then
      "ld-linux-aarch64.so.1"
    else
      null;
  dynamicLoaderDirectory = if system == "x86_64-linux" then "lib64" else "lib";
  realGlibcLoader =
    if currentDynamicLoader == null then
      null
    else
      "${glibcLoaderRoot}/${dynamicLoaderDirectory}/${dynamicLoaderFile}";
  dynamicLoaderSource =
    if currentDynamicLoader == null then
      null
    else if cfg.dynamicLoader.mode == "nix-ld" then
      "${pkgs.nix-ld}/bin/nix-ld"
    else
      realGlibcLoader;
  nixLdEnabled = cfg.enable && currentDynamicLoader != null && cfg.dynamicLoader.mode == "nix-ld";
  nixLdLibraryPath = lib.makeLibraryPath (
    [
      pkgs.glibc
      pkgs.stdenv.cc.cc.lib
    ]
    ++ cfg.nixLdLibraries
  );
  nixLdEnv = lib.optionalAttrs nixLdEnabled {
    NIX_LD = realGlibcLoader;
    NIX_LD_LIBRARY_PATH = nixLdLibraryPath;
  };
  certBundleTarget = "/etc/ssl/certs/ca-certificates.crt";
  caCertificatesEnabled = cfg.enable && cfg.caCertificates;
  caCertificatesRoot = pkgs.dockerTools.caCertificates;
  certBundleSource = "${caCertificatesRoot}${certBundleTarget}";
  caCertificatesEnv = lib.optionalAttrs caCertificatesEnabled {
    SSL_CERT_FILE = certBundleTarget;
    NIX_SSL_CERT_FILE = certBundleTarget;
    CURL_CA_BUNDLE = certBundleTarget;
    GIT_SSL_CAINFO = certBundleTarget;
  };
  glibcLoaderRoot = pkgs.runCommand "devcontainer-glibc-loader" { } ''
    mkdir -p "$out/${dynamicLoaderDirectory}"
    if [ -e ${pkgs.glibc}/${dynamicLoaderDirectory}/${dynamicLoaderFile} ]; then
      ln -s ${pkgs.glibc}/${dynamicLoaderDirectory}/${dynamicLoaderFile} "$out/${dynamicLoaderDirectory}/${dynamicLoaderFile}"
    elif [ -e ${pkgs.glibc}/lib/${dynamicLoaderFile} ]; then
      ln -s ${pkgs.glibc}/lib/${dynamicLoaderFile} "$out/${dynamicLoaderDirectory}/${dynamicLoaderFile}"
    else
      echo "glibc dynamic loader not found" >&2
      exit 1
    fi
  '';
in
{
  enabled = cfg.enable;
  dynamicLoaderMode = cfg.dynamicLoader.mode;
  realGlibcLoader = realGlibcLoader;
  nixLdEnv = nixLdEnv;
  caCertificates = lib.optionalAttrs caCertificatesEnabled {
    bundle = certBundleTarget;
    root = "${caCertificatesRoot}";
    source = certBundleSource;
  };
  env = {
    container = nixLdEnv // caCertificatesEnv;
  };
  envOrigins = {
    container =
      lib.mapAttrs (_: _: [ "compiler.fhs-runtime.nix-ld" ]) nixLdEnv
      // lib.mapAttrs (_: _: [ "compiler.fhs-runtime.ca-certificates" ]) caCertificatesEnv;
    remote = { };
    shell = { };
  };
  osReleaseText = osReleaseText;
  symlinks = [
    {
      target = "/bin/bash";
      source = "${pkgs.bashInteractive}/bin/bash";
    }
    {
      target = "/usr/bin/bash";
      source = "${pkgs.bashInteractive}/bin/bash";
    }
    {
      target = "/bin/sh";
      source = "${pkgs.bashInteractive}/bin/sh";
    }
    {
      target = "/usr/bin/sh";
      source = "${pkgs.bashInteractive}/bin/sh";
    }
    {
      target = "/usr/bin/env";
      source = "${pkgs.coreutils}/bin/env";
    }
    {
      target = "/usr/bin/tar";
      source = "${pkgs.gnutar}/bin/tar";
    }
    {
      target = "/usr/bin/gzip";
      source = "${pkgs.gzip}/bin/gzip";
    }
    {
      target = "/usr/bin/sed";
      source = "${pkgs.gnused}/bin/sed";
    }
    {
      target = "/usr/bin/grep";
      source = "${pkgs.gnugrep}/bin/grep";
    }
    {
      target = "/usr/bin/curl";
      source = "${pkgs.curl}/bin/curl";
    }
    {
      target = "/usr/bin/wget";
      source = "${pkgs.wget}/bin/wget";
    }
    {
      target = "/usr/bin/git";
      source = "${pkgs.git}/bin/git";
    }
  ]
  ++ lib.optionals (currentDynamicLoader != null) [
    {
      target = currentDynamicLoader;
      source = dynamicLoaderSource;
    }
    {
      target = "/usr/lib/libc.so.6";
      source = "${pkgs.glibc}/lib/libc.so.6";
    }
    {
      target = "/usr/lib/libstdc++.so.6";
      source = "${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6";
    }
  ];
}
