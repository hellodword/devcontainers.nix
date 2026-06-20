{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    git
    git-lfs
    openssh
    gnupg
    pinentry-curses
    delta
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.sourceControl.enable {
    environment.systemPackages = packages;
    programs.git.enable = lib.mkDefault true;
    programs.git.lfs.enable = lib.mkDefault true;
    programs.ssh.enable = lib.mkDefault true;
    devcontainer.graph.nodes."toolset/source-control" = {
      kind = "toolset";
      group = "03-source-control-tools";
      paths = packages;
      stability = "stable";
      sharing = "global";
      priority = 90;
      securityClass = "trusted";
    };
  };
}
