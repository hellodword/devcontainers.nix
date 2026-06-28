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
        tests.cases."source-control.git-ssh" = {
          tags = [
            "smoke"
            "baseline"
            "e2e-baseline"
            "source-control"
            "git"
            "ssh"
          ];
          command = [
            "bash"
            "-ic"
            "test -r /etc/gitconfig && git config --system --list >/dev/null && complete -p git >/dev/null && test -r /etc/ssh/ssh_config && ssh -G example.com >/dev/null"
          ];
        };
      };
    }

    (lib.mkIf config.devcontainer.profiles."toolset/source-control".enable {
      programs.git.enable = lib.mkDefault true;
      programs.git.lfs.enable = lib.mkDefault true;
      programs.ssh.enable = lib.mkDefault true;
    })
  ];
}
