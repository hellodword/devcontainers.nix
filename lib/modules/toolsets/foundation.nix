{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gnused
    gnugrep
    gawk
    gnutar
    gzip
    xz
    zstd
    file
    which
    less
    vim
    util-linux
    sqlite
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.foundation.enable {
    environment.systemPackages = packages;
    devcontainer.graph.nodes."toolset/foundation" = {
      kind = "toolset";
      group = "02-foundation-tools";
      paths = packages;
      stability = "very-stable";
      sharing = "global";
      priority = 95;
      securityClass = "trusted";
    };
  };
}
