{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    ripgrep
    fd
    fzf
    tree
    bat
    eza
    jq
    yq-go
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.searchNavigation.enable {
    environment.systemPackages = packages;
    devcontainer.graph.nodes."toolset/search-navigation" = {
      kind = "toolset";
      group = "05-search-navigation-tools";
      paths = packages;
      stability = "stable";
      sharing = "global";
      priority = 88;
      securityClass = "trusted";
    };
  };
}
