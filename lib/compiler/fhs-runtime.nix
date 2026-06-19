{ lib, pkgs, system }:
{ config }:
let
  cfg = config.devcontainer.compat.fhsRuntime;
  osReleaseText = ''
    NAME=devcontainer-nix
    ID=devcontainer-nix
    VERSION_ID=0
    PRETTY_NAME=devcontainer-nix
  '';
  currentDynamicLoader =
    if system == "x86_64-linux" then
      cfg.dynamicLoader.x86_64.path
    else if system == "aarch64-linux" then
      cfg.dynamicLoader.aarch64.path
    else
      null;
  currentDynamicLoaderTarget =
    if currentDynamicLoader == null then
      null
    else
      pkgs.stdenv.cc.bintools.dynamicLinker;
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
  ];
}
