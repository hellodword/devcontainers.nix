{
  pkgs,
  lib,
  compiler,
  images,
  targets,
  ...
}:

let
  reportCliTargets = builtins.filter (
    target: target.checks.reportCli or false
  ) targets.imageTargetList;
  mkReportCliCheck =
    target:
    let
      checkName =
        if builtins.length reportCliTargets == 1 then "report-cli-core" else "report-cli-${target.target}";
    in
    lib.nameValuePair checkName (
      pkgs.runCommand checkName
        {
          nativeBuildInputs = [
            pkgs.python3
          ];
        }
        ''
          python3 ${../../tests/ci/check-report-cli.py} ${
            compiler.runtimeHelpers."devcontainer-image".package
          } ${images.${target.target}.reports} ${target.target}
          touch "$out"
        ''
    );
in
lib.listToAttrs (map mkReportCliCheck reportCliTargets)
