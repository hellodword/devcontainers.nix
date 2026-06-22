{ pkgs, compiler, nixpkgs, ... }:

let
  mkToolCheck =
    name: script:
    pkgs.runCommand name
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.python3
        ];
      }
      ''
        export DEVCONTAINER_PROJECTOR=${compiler.runtimePackages."vscode-extension-projector"}
        export DEVCONTAINER_RUNNER=${compiler.runtimePackages."devcontainer-task-runner"}
        export DEVCONTAINER_DEVPKG=${compiler.runtimePackages.devpkg}
        export DEVCONTAINER_GUI_ENV_TOOL=${compiler.runtimePackages."devcontainer-gui-env"}
        export DEVPKG_NIXPKGS_REF=path:${nixpkgs.outPath}
        bash ${script}
        touch "$out"
      '';
in
{
  tool-devpkg = mkToolCheck "tool-devpkg" ../../tests/ci/check-devpkg.sh;
  tool-task-runner = mkToolCheck "tool-task-runner" ../../tests/ci/check-task-runner.sh;
  tool-vscode-extension-projector = mkToolCheck "tool-vscode-extension-projector" ../../tests/ci/check-vscode-extension-projector.sh;
  tool-gui-env = mkToolCheck "tool-gui-env" ../../tests/ci/check-gui-env.sh;
}
