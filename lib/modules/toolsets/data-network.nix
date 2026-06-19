{ lib, pkgs, config, ... }:
let
  packages = with pkgs; [
    sqlite
    postgresql
    redis
    httpie
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.dataNetwork.enable {
    devcontainer.packages = packages;
    devcontainer.graph.nodes."toolset/data-network" = {
      kind = "toolset";
      group = "08-data-network-tools";
      paths = packages;
      stability = "medium";
      sharing = "image-family";
      priority = 70;
      securityClass = "networked";
    };
  };
}
