# Store-bound internal container runtime helper executables.
{
  pkgs,
  lib,
  editor,
}:
let
  runtimeLibrary = pkgs.runCommand "devcontainer-runtime-library" { } ''
    mkdir -p "$out"
    cp ${./devcontainer-runtime/state.py} "$out/devcontainer_state.py"
    cp ${./devcontainer-runtime/cache_gc.py} "$out/devcontainer_cache_gc.py"
  '';

  writeShellApp =
    name: runtimeInputs: scriptPath:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile scriptPath;
    };

  writePythonApp =
    {
      name,
      scriptPath,
      isolated ? false,
      runtimeInputs ? [ ],
      extraSubstitutions ? "",
    }:
    pkgs.runCommand name
      {
        nativeBuildInputs = lib.optional (runtimeInputs != [ ]) pkgs.makeWrapper;
      }
      (
        ''
          mkdir -p "$out/bin"
          substitute ${scriptPath} "$out/bin/${name}" \
            --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3${lib.optionalString isolated " -I"}'
          chmod 0755 "$out/bin/${name}"
          ${extraSubstitutions}
        ''
        + lib.optionalString (runtimeInputs != [ ]) ''
          wrapProgram "$out/bin/${name}" --prefix PATH : ${lib.makeBinPath runtimeInputs}
        ''
      );

  guiEnvApp = writeShellApp "devcontainer-gui-env" [
    pkgs.coreutils
  ] ./devcontainer-gui-env/main.sh;

  nixPostBuildApp = writePythonApp {
    name = "devcontainer-nix-post-build";
    scriptPath = ./devcontainer-nix-post-build/main.py;
    isolated = true;
    extraSubstitutions = ''
      substituteInPlace "$out/bin/devcontainer-nix-post-build" \
        --replace-fail '@runtimeLibrary@' '${runtimeLibrary}' \
        --replace-fail '@nix@' '${pkgs.nix}/bin/nix' \
        --replace-fail '@zstd@' '${pkgs.zstd}/bin/zstd'
    '';
  };

  runtimeApp = writePythonApp {
    name = "devcontainer-runtime";
    scriptPath = ./devcontainer-runtime/main.py;
    isolated = true;
    extraSubstitutions = ''
      substituteInPlace "$out/bin/devcontainer-runtime" \
        --replace-fail '@runtimeLibrary@' '${runtimeLibrary}' \
        --replace-fail '@bash@' '${pkgs.bashInteractive}/bin/bash' \
        --replace-fail '@tini@' '${pkgs.tini}/bin/tini' \
        --replace-fail '@guiEnv@' '${guiEnvApp}/bin/devcontainer-gui-env' \
        --replace-fail '@nixPostBuildHook@' '${nixPostBuildApp}/bin/devcontainer-nix-post-build'
    '';
  };

  entrypointApp = pkgs.runCommand "devcontainer-entrypoint" { } ''
    mkdir -p "$out/bin"
    ln -s ${runtimeApp}/bin/devcontainer-runtime "$out/bin/devcontainer-entrypoint"
  '';

  setUserIdApp = writePythonApp {
    name = "devcontainer-set-user-id";
    scriptPath = ./devcontainer-set-user-id/main.py;
    isolated = true;
  };

  projectionTargetsJson = builtins.toJSON editor.projectionTargets;
  extensionStorePathsJson = builtins.toJSON editor.extensionStorePaths;

  taskRunnerApp = writePythonApp {
    name = "devcontainer-task-runner";
    scriptPath = ./devcontainer-task-runner/main.py;
    isolated = true;
    extraSubstitutions = ''
      substituteInPlace "$out/bin/devcontainer-task-runner" \
        --replace-fail '@runtimeLibrary@' '${runtimeLibrary}' \
        --replace-fail '@guiEnv@' '${guiEnvApp}/bin/devcontainer-gui-env' \
        --replace-fail '@nixPostBuildHook@' '${nixPostBuildApp}/bin/devcontainer-nix-post-build' \
        --replace-fail '@projectionTargetsJson@' ${lib.escapeShellArg projectionTargetsJson} \
        --replace-fail '@extensionStorePathsJson@' ${lib.escapeShellArg extensionStorePathsJson}
    '';
  };

  devpkgBin = writePythonApp {
    name = "devpkg";
    scriptPath = ./devpkg/main.py;
    runtimeInputs = [ pkgs.nix ];
  };

  devpkgCompletion = pkgs.writeTextDir "share/bash-completion/completions/devpkg" ''
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
        mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
        return
      fi

      local cmd="''${words[1]}"

      case "$cur" in
        --outputs=*)
          local output_prefix="''${cur#--outputs=}"
          mapfile -t COMPREPLY < <(compgen -W "$(devpkg complete outputs "$output_prefix" 2>/dev/null)" -- "$output_prefix")
          COMPREPLY=( "''${COMPREPLY[@]/#/--outputs=}" )
          return
          ;;
      esac

      if [[ "$prev" == "--outputs" ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$(devpkg complete outputs "$cur" 2>/dev/null)" -- "$cur")
        return
      fi

      if [[ "$cur" == --* ]]; then
        case "$cmd" in
          list | list-lib | list-dev-lib)
            mapfile -t COMPREPLY < <(compgen -W "--json" -- "$cur")
            ;;
          add-lib | add-dev-lib)
            mapfile -t COMPREPLY < <(compgen -W "--raw --outputs --outputs=" -- "$cur")
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
            [[ "$word" == "--raw" ]] && return
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

  devpkgApp = pkgs.symlinkJoin {
    name = "devpkg";
    paths = [
      devpkgBin
      devpkgCompletion
    ];
  };
in
{
  devcontainer-entrypoint = entrypointApp;
  devcontainer-runtime = runtimeApp;
  devcontainer-nix-post-build = nixPostBuildApp;
  devcontainer-set-user-id = setUserIdApp;
  devcontainer-gui-env = guiEnvApp;
  devcontainer-task-runner = taskRunnerApp;
  devpkg = devpkgApp;

  baseHelpers = [
    entrypointApp
    runtimeApp
    setUserIdApp
    guiEnvApp
    devpkgApp
  ];

  editorHelpers = [
    taskRunnerApp
  ];
}
