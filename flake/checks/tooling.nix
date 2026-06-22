{
  pkgs,
  compiler,
  nixpkgs,
  ...
}:

let
  mkToolCheck =
    name: script:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.python3
        ];
      }
      ''
        export DEVCONTAINER_PROJECTOR=${compiler.runtimePackages."vscode-extension-projector"}
        export DEVCONTAINER_RUNNER=${compiler.runtimePackages."devcontainer-task-runner"}
        export DEVCONTAINER_DEVPKG=${compiler.runtimePackages.devpkg}
        export DEVCONTAINER_GUI_ENV_TOOL=${compiler.runtimePackages."devcontainer-gui-env"}
        export DEVPKG_NIXPKGS_REF=path:${nixpkgs.outPath}
        python3 ${script}
        touch "$out"
      '';
in
{
  tool-devpkg = mkToolCheck "tool-devpkg" ../../tests/ci/check-devpkg.py;
  tool-task-runner = mkToolCheck "tool-task-runner" ../../tests/ci/check-task-runner.py;
  tool-vscode-extension-projector = mkToolCheck "tool-vscode-extension-projector" ../../tests/ci/check-vscode-extension-projector.py;
  tool-gui-env = mkToolCheck "tool-gui-env" ../../tests/ci/check-gui-env.py;

  script-quality =
    pkgs.runCommand "script-quality"
      {
        nativeBuildInputs = [
          pkgs.findutils
          pkgs.python3
          pkgs.shellcheck
        ];
      }
      ''
        export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
        find ${../..}/runtime ${../..}/tests/ci ${../..}/tests/smoke -name '*.py' -print0 \
          | xargs -0 python3 -m py_compile
        find ${../..}/runtime ${../..}/tests/ci ${../..}/tests/smoke -name '*.sh' -print0 \
          | xargs -0 shellcheck
        touch "$out"
      '';
}
