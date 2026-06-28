{
  pkgs,
  lib,
  images,
  ...
}:

let
  repoRoot = ../../..;
  checkReports = ../../../tests/ci/check-reports.py;
  checkSmokePlan = ../../../tests/ci/check-smoke-plan.py;
  checkHermeticDefaults = ../../../tests/ci/check-hermetic-default-checks.py;
  reportLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: image: ''
      echo "checking reports for ${name}"
      python3 ${checkReports} ${image.reports} ${name}
    '') images
  );
  reportChecks = lib.mapAttrs' (
    name: image:
    lib.nameValuePair "reports-${name}" (
      pkgs.runCommand "reports-${name}"
        {
          nativeBuildInputs = [ pkgs.python3 ];
        }
        ''
          export CHECK_SMOKE_PLAN=${checkSmokePlan}
          python3 ${checkReports} ${image.reports} ${name}
          touch "$out"
        ''
    )
  ) images;
  smokePlanLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: image: ''
      echo "checking smoke plan for ${name}"
      python3 ${checkSmokePlan} ${image.smoke} ${image.profile-report-json} ${name}
    '') images
  );
in
reportChecks
// {
  contracts-reports-all =
    pkgs.runCommand "contracts-reports-all" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        export CHECK_SMOKE_PLAN=${checkSmokePlan}
        ${reportLines}
        touch "$out"
      '';

  contracts-smoke-plan-all =
    pkgs.runCommand "contracts-smoke-plan-all" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        ${smokePlanLines}
        touch "$out"
      '';

  contracts-hermetic-checks =
    pkgs.runCommand "contracts-hermetic-checks" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${checkHermeticDefaults} ${repoRoot}
        touch "$out"
      '';
}
