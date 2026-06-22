{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = [
    config.programs.git.package
    pkgs.git-lfs
    config.programs.ssh.package
    pkgs.gnupg
    pkgs.pinentry-curses
    pkgs.delta
  ];
in
{
  config = lib.mkMerge [
    {
      devcontainer.profiles."toolset/source-control" = {
        kind = "toolset";
        group = "03-source-control-tools";
        packages = packages;
        priority = 90;
        stability = "stable";
        sharing = "global";
        securityClass = "trusted";
        provides.commands = [
          "git"
          "git-lfs"
          "ssh"
          "gpg"
          "pinentry-curses"
          "delta"
        ];
        tests.capabilities = [ "source-control.git-ssh" ];
      };
    }

    (lib.mkIf config.devcontainer.profiles."toolset/source-control".enable {
      programs.git.enable = lib.mkDefault true;
      programs.git.lfs.enable = lib.mkDefault true;
      programs.ssh.enable = lib.mkDefault true;
    })
  ];
}
