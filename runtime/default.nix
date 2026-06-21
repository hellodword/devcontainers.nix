{ pkgs, lib }:
let
  writeShellApp =
    name: runtimeInputs: scriptPath:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile scriptPath;
    };
  devpkgApp = writeShellApp "devpkg" [
    pkgs.bash
    pkgs.coreutils
    pkgs.jq
    pkgs.nix
  ] ./devpkg/main.sh;
  devpkgCompletionText = ''
    _devpkg()
    {
      local cur prev words cword

      if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -n = || return
      else
        COMPREPLY=()
        words=("''${COMP_WORDS[@]}")
        cword=$COMP_CWORD
        cur="''${COMP_WORDS[COMP_CWORD]}"
        prev="''${COMP_WORDS[COMP_CWORD - 1]}"
      fi

      local commands="add install remove rm uninstall list ls search add-lib remove-lib list-lib add-dev-lib remove-dev-lib list-dev-lib help -h --help"
      if (( cword == 1 )); then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return
      fi

      local cmd="''${words[1]}"
      case "$cmd" in
        install) cmd="add" ;;
        rm | uninstall) cmd="remove" ;;
        ls) cmd="list" ;;
      esac

      case "$cur" in
        --outputs=*)
          local output_prefix="''${cur#--outputs=}"
          COMPREPLY=( $(compgen -W "$(devpkg complete outputs "$output_prefix" 2>/dev/null)" -- "$output_prefix") )
          COMPREPLY=( "''${COMPREPLY[@]/#/--outputs=}" )
          return
          ;;
      esac

      if [ "$prev" = "--outputs" ]; then
        COMPREPLY=( $(compgen -W "$(devpkg complete outputs "$cur" 2>/dev/null)" -- "$cur") )
        return
      fi

      if [[ "$cur" == --* ]]; then
        case "$cmd" in
          list | list-lib | list-dev-lib)
            COMPREPLY=( $(compgen -W "--json" -- "$cur") )
            ;;
          add-lib | add-dev-lib)
            COMPREPLY=( $(compgen -W "--raw --outputs --outputs=" -- "$cur") )
            ;;
        esac
        return
      fi

      case "$cmd" in
        add | search)
          mapfile -t COMPREPLY < <(devpkg complete packages "$cur" 2>/dev/null)
          ;;
        remove)
          mapfile -t COMPREPLY < <(devpkg complete installed main "$cur" 2>/dev/null)
          ;;
        add-lib | add-dev-lib)
          local word
          for word in "''${words[@]:2:cword-2}"; do
            [ "$word" = "--raw" ] && return
          done
          mapfile -t COMPREPLY < <(devpkg complete packages "$cur" 2>/dev/null)
          ;;
        remove-lib)
          mapfile -t COMPREPLY < <(devpkg complete installed runtime "$cur" 2>/dev/null)
          ;;
        remove-dev-lib)
          mapfile -t COMPREPLY < <(devpkg complete installed build "$cur" 2>/dev/null)
          ;;
      esac
    }

    complete -F _devpkg devpkg
  '';
  devpkgCompletion = pkgs.writeTextDir "share/bash-completion/completions/devpkg" devpkgCompletionText;
in
{
  "devcontainer-entrypoint" = writeShellApp "devcontainer-entrypoint" [
    pkgs.coreutils
  ] ./devcontainer-entrypoint/main.sh;
  "devcontainer-gui-env" = writeShellApp "devcontainer-gui-env" [
    pkgs.coreutils
  ] ./devcontainer-gui-env/main.sh;
  "devcontainer-task-runner" = writeShellApp "devcontainer-task-runner" [
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.jq
    pkgs.moreutils
  ] ./devcontainer-task-runner/main.sh;
  "vscode-extension-projector" = writeShellApp "vscode-extension-projector" [
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.jq
  ] ./vscode-extension-projector/main.sh;
  devpkg = pkgs.symlinkJoin {
    name = "devpkg";
    paths = [
      devpkgApp
      devpkgCompletion
    ];
  };
  "devcontainer-image" = writeShellApp "devcontainer-image" [
    pkgs.bash
    pkgs.coreutils
    pkgs.diffutils
    pkgs.gnugrep
    pkgs.jq
  ] ./devcontainer-image/main.sh;
}
