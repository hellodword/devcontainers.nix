{ pkgs, lib }:
let
  writeShellApp =
    name: runtimeInputs: scriptPath:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile scriptPath;
    };
  writePythonApp =
    name: runtimeInputs: scriptPath:
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      (
        ''
          mkdir -p "$out/bin"
          substitute ${scriptPath} "$out/bin/${name}" \
            --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
          chmod +x "$out/bin/${name}"
        ''
        + lib.optionalString (runtimeInputs != [ ]) ''
          wrapProgram "$out/bin/${name}" --prefix PATH : ${lib.makeBinPath runtimeInputs}
        ''
      );
  devpkgApp = writePythonApp "devpkg" [
    pkgs.nix
  ] ./devpkg/main.py;
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
  packages = rec {
    "devcontainer-entrypoint" = writeShellApp "devcontainer-entrypoint" [
      pkgs.coreutils
    ] ./devcontainer-entrypoint/main.sh;
    "devcontainer-gui-env" = writeShellApp "devcontainer-gui-env" [
      pkgs.coreutils
    ] ./devcontainer-gui-env/main.sh;
    "devcontainer-task-runner" =
      writePythonApp "devcontainer-task-runner" [ ]
        ./devcontainer-task-runner/main.py;
    "vscode-extension-projector" =
      writePythonApp "vscode-extension-projector" [ ]
        ./vscode-extension-projector/main.py;
    devpkg = pkgs.symlinkJoin {
      name = "devpkg";
      paths = [
        devpkgApp
        devpkgCompletion
      ];
    };
    "devcontainer-image" = writePythonApp "devcontainer-image" [ ] ./devcontainer-image/main.py;
  };
  helperDefs = {
    "devcontainer-entrypoint" = {
      order = 10;
      publicPackage = false;
      installInImage = true;
    };
    "devcontainer-gui-env" = {
      order = 30;
      publicPackage = true;
      installInImage = true;
      checkName = "gui-env";
      checkScript = ../tests/ci/check-gui-env.py;
      checkEnvName = "DEVCONTAINER_GUI_ENV_TOOL";
    };
    "devcontainer-task-runner" = {
      order = 20;
      publicPackage = true;
      installInImage = true;
      checkName = "task-runner";
      checkScript = ../tests/ci/check-task-runner.py;
      checkEnvName = "DEVCONTAINER_RUNNER";
      securityCapabilities.redactsLifecycleLogs = true;
    };
    "vscode-extension-projector" = {
      order = 40;
      publicPackage = true;
      installInImage = true;
      checkName = "vscode-extension-projector";
      checkScript = ../tests/ci/check-vscode-extension-projector.py;
      checkEnvName = "DEVCONTAINER_PROJECTOR";
      securityCapabilities.redactsProjectionLogs = true;
    };
    devpkg = {
      order = 50;
      publicPackage = true;
      installInImage = true;
      checkName = "devpkg";
      checkScript = ../tests/ci/check-devpkg.py;
      checkEnvName = "DEVCONTAINER_DEVPKG";
    };
    "devcontainer-image" = {
      order = 60;
      publicPackage = true;
      installInImage = true;
    };
  };
  helpers = lib.mapAttrs (
    name: metadata:
    metadata
    // {
      inherit name;
      package = packages.${name};
    }
  ) helperDefs;
  rawHelperList = builtins.attrValues helpers;
  helperList =
    assert lib.assertMsg (lib.all (
      helper: helper ? order && builtins.isInt helper.order
    ) rawHelperList) "runtime/default.nix: every helperDef must define integer order";
    let
      helperOrders = map (helper: helper.order) rawHelperList;
    in
    assert lib.assertMsg (
      builtins.length (lib.unique helperOrders) == builtins.length helperOrders
    ) "runtime/default.nix: helperDef order values must be unique";
    lib.sort (a: b: a.order < b.order) rawHelperList;
in
packages
// {
  __helpers = helpers;
  __helperList = helperList;
}
