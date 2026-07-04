{
  lib,
  images,
  contractLib,
  ...
}:

let
  requiredSecurityChecks = [
    "secretScan"
    "dockerSocket"
    "dockerDaemon"
    "extensionArtifacts"
    "lifecycleLogRedaction"
    "extensionProjectionLogRedaction"
    "shellInitSideEffects"
  ];
  evidenceValid =
    check:
    let
      evidence = check.evidence or { };
      findings = evidence.findings or [ ];
    in
    builtins.isList findings
    && (evidence.findingCount or null) == builtins.length findings
    && lib.all (
      finding:
      builtins.isAttrs finding
      && contractLib.nonEmptyString (finding.source or null)
      && contractLib.nonEmptyString (finding.path or null)
      && contractLib.nonEmptyString (finding.field or null)
      && builtins.isInt (finding.count or null)
      && finding.count >= 1
    ) findings;
  perImage = lib.mapAttrsToList (
    name: image:
    let
      report = image.security.report;
      checksByName = report.checks or { };
      missingChecks = builtins.filter (
        checkName: !(builtins.hasAttr checkName checksByName)
      ) requiredSecurityChecks;
      failedChecks = builtins.filter (
        checkName: ((checksByName.${checkName} or { }).status or null) != "pass"
      ) requiredSecurityChecks;
      invalidEvidence = builtins.filter (checkName: !(evidenceValid checksByName.${checkName})) (
        builtins.attrNames checksByName
      );
      checks = {
        imageMatches = (report.image or null) == name;
        requiredChecksPresent = missingChecks == [ ];
        requiredChecksPass = failedChecks == [ ];
        topLevelFindingsEmpty = (report.findings or [ ]) == [ ];
        evidenceShape = invalidEvidence == [ ];
      };
    in
    {
      inherit name checks;
      details = {
        inherit
          missingChecks
          failedChecks
          invalidEvidence
          ;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-security = contractLib.mkAssertedJsonCheck "contracts-reports-security" [
    allValid
  ] { images = perImage; };
}
