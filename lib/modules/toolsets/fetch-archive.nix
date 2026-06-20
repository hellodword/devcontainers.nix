{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    curl
    wget
    aria2
    rsync
    unzip
    zip
    p7zip
    bzip2
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.fetchArchive.enable {
    environment.systemPackages = packages;
    devcontainer.graph.nodes."toolset/fetch-archive" = {
      kind = "toolset";
      group = "04-fetch-archive-tools";
      paths = packages;
      stability = "stable";
      sharing = "global";
      priority = 88;
      securityClass = "networked";
    };
  };
}
