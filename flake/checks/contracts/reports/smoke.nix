{
  lib,
  images,
  contractLib,
  ...
}:

let
  validStringList = value: builtins.isList value && lib.all contractLib.nonEmptyString value;
  validScript =
    script:
    builtins.isAttrs script
    && contractLib.nonEmptyString (script.command or null)
    && contractLib.nonEmptyString (script.shell or null)
    && builtins.isBool (script.interactive or null);
  validSmokeTest =
    test:
    builtins.isAttrs test
    && contractLib.nonEmptyString (test.id or null)
    && validStringList (test.tags or null)
    && builtins.elem "smoke" test.tags
    && builtins.isList (test.scripts or null)
    && test.scripts != [ ]
    && lib.all validScript test.scripts
    && validStringList (test.requires or null)
    && builtins.isInt (test.timeoutSeconds or null)
    && test.timeoutSeconds >= 1;
  perImage = lib.mapAttrsToList (
    name: image:
    let
      smokePlan = image.reportData.smokePlan;
      tests = image.tests.tests;
      testIds = map (test: test.id) tests;
      caseIds = image.tests.caseIds;
      declaredCaseIds = image.tests.declaredCaseIds;
      missingDeclaredCases = builtins.filter (caseId: !(builtins.elem caseId caseIds)) declaredCaseIds;
      checks = {
        smokePlanMatchesCompiler = smokePlan.tests == tests && smokePlan.caseIds == caseIds;
        caseIdsPresent = caseIds != [ ];
        caseIdsSortedUnique = caseIds == lib.sort lib.lessThan (lib.unique testIds);
        noDuplicateTestIds = builtins.length testIds == builtins.length (lib.unique testIds);
        testsValid = lib.all validSmokeTest tests;
        declaredCasesResolved = missingDeclaredCases == [ ];
        imagePlanCount = image.reportData.imagePlan.smokeTestCount == builtins.length tests;
      };
    in
    {
      inherit name checks;
      details = {
        inherit missingDeclaredCases;
        caseIds = caseIds;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-smoke = contractLib.mkAssertedJsonCheck "contracts-reports-smoke" [ allValid ] {
    images = perImage;
  };
}
