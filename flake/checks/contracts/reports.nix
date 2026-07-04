{
  pkgs,
  lib,
  images,
  targets,
  ...
}:

let
  repoRoot = ../../..;
  contractLib = import ./lib.nix { inherit lib pkgs; };
  contractArgs = {
    inherit
      pkgs
      lib
      images
      targets
      contractLib
      ;
  };
  nixReportContracts = lib.foldl' (acc: path: acc // (import path contractArgs)) { } [
    ./reports/env.nix
    ./reports/profiles.nix
    ./reports/metadata.nix
    ./reports/layers.nix
    ./reports/extensions.nix
    ./reports/filesystem.nix
    ./reports/fonts.nix
    ./reports/security.nix
    ./reports/smoke.nix
  ];
  nixReportContractLines = lib.concatMapStringsSep "\n" (drv: "test -e ${drv}") (
    builtins.attrValues nixReportContracts
  );
  checkReports = ../../../tests/ci/check-reports.py;
  checkSmokePlan = ../../../tests/ci/check-smoke-plan.py;
  checkHermeticDefaults = ../../../tests/ci/check-hermetic-default-checks.py;
  checkMetadataSchema = ../../../tests/ci/check-devcontainer-metadata-schema.py;
  pythonWithJsonschema = pkgs.python3.withPackages (ps: [ ps.jsonschema ]);
  devcontainersSpec = pkgs.fetchFromGitHub {
    owner = "devcontainers";
    repo = "spec";
    rev = "c95ffeed1d059abfe9ffbe79762dc2fa4e7c2421";
    hash = "sha256-NYaeKpbRy+pRbPCuyZ7t6KiOmBerCCFBG2jAKrfgEMI=";
  };
  devcontainersSchemaDir = "${devcontainersSpec}/schemas";
  targetPolicyPath =
    name:
    let
      checks = targets.imageTargets.${name}.checks or { };
    in
    pkgs.writeText "target-policy-${name}.json" (
      builtins.toJSON {
        requiredProfiles = checks.requiredProfiles or [ ];
        requiredCommands = checks.requiredCommands or [ ];
      }
    );
  reportLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: image: ''
      echo "checking reports for ${name}"
      python3 ${checkReports} ${image.reports} ${name} ${targetPolicyPath name}
      python3 ${checkMetadataSchema} ${image.metadata-label-json} ${image.metadata-merged-preview-json} ${devcontainersSchemaDir} ${name}
    '') images
  );
  reportChecks = lib.mapAttrs' (
    name: image:
    lib.nameValuePair "reports-${name}" (
      pkgs.runCommand "reports-${name}"
        {
          nativeBuildInputs = [ pythonWithJsonschema ];
        }
        ''
          export PYTHONPATH=${../../../tests/ci}
          export CHECK_SMOKE_PLAN=${checkSmokePlan}
          python3 ${checkReports} ${image.reports} ${name} ${targetPolicyPath name}
          python3 ${checkMetadataSchema} ${image.metadata-label-json} ${image.metadata-merged-preview-json} ${devcontainersSchemaDir} ${name}
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
// nixReportContracts
// {
  contracts-reports-all =
    pkgs.runCommand "contracts-reports-all" { nativeBuildInputs = [ pythonWithJsonschema ]; }
      ''
        export PYTHONPATH=${../../../tests/ci}
        export CHECK_SMOKE_PLAN=${checkSmokePlan}
        ${reportLines}
        ${nixReportContractLines}
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
