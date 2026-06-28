{ lib }:
{
  config,
  compiledProfiles,
}:
let
  topLevelCases = config.devcontainer.tests.cases;
  profileCases = compiledProfiles.testCases;
  topLevelCaseIds = lib.sort lib.lessThan (builtins.attrNames topLevelCases);
  profileCaseIds =
    compiledProfiles.testCaseIds or (lib.sort lib.lessThan (builtins.attrNames profileCases));
  declaredCaseIds = topLevelCaseIds ++ profileCaseIds;
  groupedCaseEntries = lib.groupBy (entry: entry.id) (
    (lib.mapAttrsToList (caseId: case: {
      id = caseId;
      inherit case;
      origin = "top-level";
    }) topLevelCases)
    ++ (lib.mapAttrsToList (caseId: case: {
      id = caseId;
      inherit case;
      origin = "profile";
    }) profileCases)
  );
  conflictingCaseEntries =
    lib.mapAttrsToList
      (caseId: entries: {
        inherit caseId;
        origins = lib.unique (map (entry: entry.origin) entries);
      })
      (
        lib.filterAttrs (
          _: entries: builtins.length (lib.unique (map (entry: entry.case) entries)) > 1
        ) groupedCaseEntries
      );
  cases = lib.mapAttrs (_: entries: (builtins.head entries).case) groupedCaseEntries;
  caseIds = lib.sort lib.lessThan (builtins.attrNames cases);
  tests = map (
    caseId:
    let
      case = cases.${caseId};
    in
    {
      id = caseId;
      inherit (case)
        tags
        command
        requires
        timeoutSeconds
        ;
    }
  ) caseIds;
in
if conflictingCaseEntries != [ ] then
  builtins.throw "conflicting devcontainer smoke cases: ${builtins.toJSON conflictingCaseEntries}"
else
  {
    inherit
      declaredCaseIds
      caseIds
      tests
      ;
    report = {
      declaredCases = declaredCaseIds;
      resolvedCases = caseIds;
      testCount = builtins.length tests;
    };
  }
