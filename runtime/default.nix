{ pkgs, lib }:
let
  runtimeLibrary = pkgs.runCommand "devcontainer-runtime-library" { } ''
    mkdir -p "$out"
    cp ${./devcontainer-set-user-id/main.py} "$out/devcontainer_identity.py"
    cp ${./devcontainer-runtime/state.py} "$out/devcontainer_state.py"
  '';
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
            --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3${
              lib.optionalString (builtins.elem name [
                "devcontainer-runtime"
                "devcontainer-set-user-id"
              ]) " -I"
            }'
          chmod +x "$out/bin/${name}"
        ''
        +
          lib.optionalString
            (builtins.elem name [
              "devcontainer-runtime"
              "devcontainer-task-runner"
            ])
            ''
              substituteInPlace "$out/bin/${name}" --replace-fail '@runtimeLibrary@' '${runtimeLibrary}'
            ''
        + lib.optionalString (name == "devcontainer-runtime") ''
          substituteInPlace "$out/bin/${name}" \
            --replace-fail '@bash@' '${pkgs.bashInteractive}/bin/bash' \
            --replace-fail '@tini@' '${pkgs.tini}/bin/tini' \
            --replace-fail '@session@' '${./devcontainer-entrypoint/main.sh}'
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

      local commands="add remove list search add-lib remove-lib list-lib add-dev-lib remove-dev-lib list-dev-lib help -h --help"
      if (( cword == 1 )); then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return
      fi

      local cmd="''${words[1]}"

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
    # Start Python in isolated mode directly: a root startup must not evaluate
    # BASH_ENV, PYTHONPATH, or other user-provided shell/Python startup files.
    "devcontainer-entrypoint" = pkgs.runCommand "devcontainer-entrypoint" { } ''
      mkdir -p "$out/bin"
      ln -s ${packages.devcontainer-runtime}/bin/devcontainer-runtime "$out/bin/devcontainer-entrypoint"
    '';
    "devcontainer-runtime" = writePythonApp "devcontainer-runtime" [ ] ./devcontainer-runtime/main.py;
    "devcontainer-gui-env" = writeShellApp "devcontainer-gui-env" [
      pkgs.coreutils
    ] ./devcontainer-gui-env/main.sh;
    "devcontainer-task-runner" =
      writePythonApp "devcontainer-task-runner" [ ]
        ./devcontainer-task-runner/main.py;
    "vscode-extension-projector" =
      writePythonApp "vscode-extension-projector" [ ]
        ./vscode-extension-projector/main.py;
    "devcontainer-set-user-id" =
      writePythonApp "devcontainer-set-user-id" [ ]
        ./devcontainer-set-user-id/main.py;
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
    "devcontainer-runtime" = {
      order = 15;
      publicPackage = false;
      installInImage = true;
      checkName = "runtime";
      checkScript = ../tests/ci/check-runtime.py;
      checkEnvName = "DEVCONTAINER_RUNTIME";
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
    "devcontainer-set-user-id" = {
      order = 45;
      publicPackage = true;
      installInImage = true;
      checkName = "set-user-id";
      checkScript = ../tests/ci/check-set-user-id.py;
      checkEnvName = "DEVCONTAINER_SET_USER_ID";
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
