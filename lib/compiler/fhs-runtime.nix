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
  currentDynamicLoaderTarget =
    if currentDynamicLoader == null then null else "${glibcLoaderRoot}/lib64/ld-linux-x86-64.so.2";
  glibcLoaderRoot = pkgs.runCommand "devcontainer-glibc-loader" { } ''
    mkdir -p "$out/lib64"
    if [ -e ${pkgs.glibc}/lib64/ld-linux-x86-64.so.2 ]; then
      ln -s ${pkgs.glibc}/lib64/ld-linux-x86-64.so.2 "$out/lib64/ld-linux-x86-64.so.2"
    elif [ -e ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 ]; then
      ln -s ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 "$out/lib64/ld-linux-x86-64.so.2"
    else
      echo "glibc dynamic loader not found" >&2
      exit 1
    fi
  '';
in
{
  enabled = cfg.enable;
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
      source = currentDynamicLoaderTarget;
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
