{
  lib,
  images,
  contractLib,
  ...
}:

let
  evidenceValid =
    check:
    let
      evidence = check.evidence or null;
      findings = if builtins.isAttrs evidence then evidence.findings or null else null;
    in
    builtins.isAttrs evidence
    && builtins.isList findings
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
  checkValid =
    check:
    builtins.isAttrs check
    && (check.status or null) == "pass"
    && contractLib.nonEmptyString (check.summary or null)
    && evidenceValid check;
  perImage = lib.mapAttrsToList (
    name: image:
    let
      report = image.security.report;
      rawChecks = report.checks or null;
      checksByName = if builtins.isAttrs rawChecks then rawChecks else { };
      invalidChecks = builtins.filter (checkName: !(checkValid checksByName.${checkName})) (
        builtins.attrNames checksByName
      );
      checks = {
        imageMatches = (report.image or null) == name;
        checksIsObject = builtins.isAttrs rawChecks;
        checksPresent = checksByName != { };
        topLevelFindingsEmpty = (report.findings or [ ]) == [ ];
        checkShape = invalidChecks == [ ];
      };
    in
    {
      inherit name checks;
      details = {
        inherit invalidChecks;
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
