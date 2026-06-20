{
  pkgs,
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
  config.devcontainer.profiles."toolset/search-navigation" = {
    kind = "toolset";
    group = "05-search-navigation-tools";
    packages = packages;
    priority = 88;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "rg"
      "fd"
      "fzf"
      "tree"
      "bat"
      "eza"
      "jq"
      "yq"
    ];
  };
}
