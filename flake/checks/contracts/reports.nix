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
    ./reports/fhs.nix
    ./reports/filesystem.nix
    ./reports/fonts.nix
    ./reports/security.nix
    ./reports/smoke.nix
  ];
  nixReportContractLines = lib.concatMapStringsSep "\n" (drv: "test -e ${drv}") (
    builtins.attrValues nixReportContracts
  );
  checkReports = ../../../tests/ci/check-report-bundle.py;
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
  reportLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: image: ''
      echo "checking reports for ${name}"
      python3 ${checkReports} ${image.reports} ${name}
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
          python3 ${checkReports} ${image.reports} ${name}
          python3 ${checkMetadataSchema} ${image.metadata-label-json} ${image.metadata-merged-preview-json} ${devcontainersSchemaDir} ${name}
          touch "$out"
        ''
    )
  ) images;
in
reportChecks
// nixReportContracts
// {
  contracts-reports-all =
    pkgs.runCommand "contracts-reports-all" { nativeBuildInputs = [ pythonWithJsonschema ]; }
      ''
        export PYTHONPATH=${../../../tests/ci}
        ${reportLines}
        ${nixReportContractLines}
        touch "$out"
      '';

  contracts-hermetic-checks =
    pkgs.runCommand "contracts-hermetic-checks" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${checkHermeticDefaults} ${repoRoot}
        touch "$out"
      '';
}
