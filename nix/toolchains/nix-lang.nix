# Nix language servers, formatters, static analyzers, and man pages.
{ pkgs }:
let
  usrPackages = with pkgs; [
    nixd
    nil
    man
    nixfmt
    alejandra
    statix
    deadnix
    treefmt
  ];
in
{
  inherit usrPackages;
  storeDeps = usrPackages;
  pathSegments = [ ];
  cacheEnv = { };
  devEnv = { };
  env = { };
}
