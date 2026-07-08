{
  pkgs,
  lib,
  nixpkgs,
  compiler,
  ...
}:

let
  fixtures = import ./fixtures.nix {
    inherit
      pkgs
      lib
      nixpkgs
      compiler
      ;
  };
  inherit (fixtures)
    apiEvalImage
    apiVscodeMachineSettings
    apiVscodeMachineSettingsPaths
    apiWorkspacePathSegments
    defaultFieldsScript
    displayDrv
    envCycleRejected
    envExpansion
    envMaxDepthRejected
    expectedVscodeMachineSettingsPaths
    invalidEtcModeRejected
    invalidEtcOwnerRejected
    invalidEtcTargetRejected
    invalidFilesystemModeRejected
    invalidFilesystemOwnerRejected
    invalidFilesystemPathRejected
    missingPresetEnvRejected
    pathCommandScript
    remoteEnvExpansion
    uniqueDrvPaths
    withoutDrvPaths
    ;
in
{
  contracts-compiler-env =
    assert envExpansion.XDG_DATA_HOME == "/home/vscode/.local/share";
    assert envExpansion.BIN == "/home/vscode/.local/share/bin";
    assert envExpansion.PATH_LIST == "/home/vscode/.local/share/bin:/usr/bin";
    assert envExpansion.BRACED_SUFFIX == "tool-suffix";
    assert envExpansion.TAIL == "/opt/tool";
    assert envExpansion.EXTERNAL == "$DEVCONTAINER_WORKSPACE";
    assert remoteEnvExpansion.CHILD == "/base/child";
    assert remoteEnvExpansion.KEEP == "$UNDEFINED_REMOTE";
    assert envCycleRejected;
    assert envMaxDepthRejected;
    assert
      uniqueDrvPaths == [
        (displayDrv pkgs.hello)
        (displayDrv pkgs.git)
      ];
    assert withoutDrvPaths == [ (displayDrv pkgs.git) ];
    assert missingPresetEnvRejected;
    assert invalidEtcModeRejected;
    assert invalidEtcOwnerRejected;
    assert invalidEtcTargetRejected;
    assert invalidFilesystemPathRejected;
    assert invalidFilesystemModeRejected;
    assert invalidFilesystemOwnerRejected;
    assert apiEvalImage.env.workspace.lateBound;
    assert !(builtins.hasAttr "WORKSPACE" apiEvalImage.env.containerEnv);
    assert apiEvalImage.env.workspace.pathSegments == apiWorkspacePathSegments;
    assert
      apiEvalImage.env.staticPathSegments
      == builtins.filter (
        segment: !(builtins.elem segment apiEvalImage.env.workspace.pathSegments)
      ) apiEvalImage.env.pathSegments;
    assert
      apiEvalImage.env.containerEnv.PATH == lib.concatStringsSep ":" apiEvalImage.env.staticPathSegments;
    assert apiEvalImage.env.runtimePATH == lib.concatStringsSep ":" apiEvalImage.env.pathSegments;
    assert apiEvalImage.metadata.mergedPreview.containerEnv.WORKSPACE == "\${containerWorkspaceFolder}";
    assert apiEvalImage.env.containerEnv.API_BOOL == "1";
    assert apiEvalImage.env.containerEnv.TZDIR == "/etc/zoneinfo";
    assert
      apiEvalImage.env.containerEnv.DEVCONTAINER_FLAKE_INPUTS
      == "/usr/share/devcontainer/flake-inputs.json";
    assert apiEvalImage.flakeInputs.manifest.inputs.nixpkgs.rev == nixpkgs.rev;
    assert apiEvalImage.flakeInputs.manifest.inputs.nixpkgs.outPath == toString nixpkgs.outPath;
    assert builtins.elem "/etc/api/example.conf" (map (entry: entry.path) apiEvalImage.environment.etc);
    assert builtins.elem "man" apiEvalImage.environment.report.extraOutputsToInstall;
    assert lib.hasInfix "complete -p git" apiEvalImage.shell.bashrcText;
    assert lib.hasInfix "share/bash-completion/completions/git" apiEvalImage.shell.bashrcText;
    assert apiVscodeMachineSettings.settings == apiEvalImage.profiles.settings;
    assert
      pathCommandScript.command == builtins.readFile ../../../../runtime/devcontainer-gui-env/main.sh;
    assert pathCommandScript.shell == "bash";
    assert !(pathCommandScript.interactive);
    assert defaultFieldsScript.command == "true";
    assert defaultFieldsScript.shell == "bash";
    assert !(defaultFieldsScript.interactive);
    assert apiVscodeMachineSettingsPaths == expectedVscodeMachineSettingsPaths;
    assert lib.all (
      entry:
      entry.rootMode == "1777"
      && entry.dataMode == "1777"
      && entry.machineMode == "1777"
      && entry.settingsMode == "0444"
      && entry.owner == "root:root"
    ) apiVscodeMachineSettings.paths;
    pkgs.writeText "contracts-compiler-env.json" (builtins.toJSON apiEvalImage.environment.report);
}
