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
        tests.smoke = [
          {
            name = "git-system-config";
            command = [
              "bash"
              "-lc"
              "test -r /etc/gitconfig && git config --system --list >/dev/null"
            ];
          }
          {
            name = "git-bash-completion";
            command = [
              "bash"
              "-ic"
              "COMP_WORDS=(git che) && COMP_CWORD=1 && _comp_complete_load git >/dev/null 2>&1 || true; complete -p git >/dev/null && COMP_WORDS=(git che) && COMP_CWORD=1 && __git_wrap__git_main git che git && printf '%s\\n' \"\${COMPREPLY[@]}\" | grep -Fx 'checkout ' >/dev/null"
            ];
          }
          {
            name = "ssh-global-config";
            command = [
              "bash"
              "-lc"
              "test -r /etc/ssh/ssh_config && ssh -G example.com >/dev/null"
            ];
          }
        ];
      };
    }

    (lib.mkIf config.devcontainer.profiles."toolset/source-control".enable {
      programs.git.enable = lib.mkDefault true;
      programs.git.lfs.enable = lib.mkDefault true;
      programs.ssh.enable = lib.mkDefault true;
    })
  ];
}
