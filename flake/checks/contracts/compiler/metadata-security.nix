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
    invalidKnownHostsRejected
    missingCompanionToolRejected
    metadataRunArgsUserRejected
    unsupportedSudoRejected
    ;
  securityReport = apiEvalImage.security.report;
  rawSecurityChecks = securityReport.checks or null;
  securityChecks = if builtins.isAttrs rawSecurityChecks then rawSecurityChecks else { };
  securityEvidenceValid =
    check:
    let
      evidence = check.evidence or null;
      findings = if builtins.isAttrs evidence then evidence.findings or null else null;
    in
    builtins.isAttrs evidence
    && builtins.isList findings
    && (evidence.findingCount or null) == builtins.length findings
    && findings == [ ];
  securityCheckValid =
    check:
    builtins.isAttrs check
    && (check.status or null) == "pass"
    && builtins.isString (check.summary or null)
    && check.summary != ""
    && securityEvidenceValid check;
in
{
  contracts-compiler-metadata =
    assert apiEvalImage.metadata.mergedPreview.userEnvProbe == "loginInteractiveShell";
    assert !(builtins.hasAttr "PATH" (apiEvalImage.metadata.mergedPreview.containerEnv or { }));
    assert builtins.hasAttr "postStartCommand" apiEvalImage.metadata.mergedPreview;
    assert securityReport.image == "api-eval";
    assert builtins.isAttrs rawSecurityChecks;
    assert securityChecks != { };
    assert lib.all securityCheckValid (builtins.attrValues securityChecks);
    assert securityReport.findings == [ ];
    assert invalidKnownHostsRejected;
    assert unsupportedSudoRejected;
    assert missingCompanionToolRejected;
    assert metadataRunArgsUserRejected;
    pkgs.writeText "contracts-compiler-metadata.json" (
      builtins.toJSON apiEvalImage.metadata.schemaReport
    );
}
