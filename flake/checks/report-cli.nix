{
  pkgs,
  lib,
  compiler,
  images,
  targets,
  ...
}:

let
  mkReportCliCheck =
    target:
    let
      checkName = "report-cli-${target.target}";
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
lib.listToAttrs (map mkReportCliCheck targets.imageTargetList)
