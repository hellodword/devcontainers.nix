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
  normalizeCommand =
    caseId: command:
    let
      normalized = if builtins.typeOf command == "path" then builtins.readFile command else command;
    in
    assert lib.assertMsg (normalized != "") "smoke case ${caseId} script command must not be empty";
    normalized;
  normalizeScript = caseId: script: {
    command = normalizeCommand caseId script.command;
    inherit (script)
      shell
      interactive
      ;
  };
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
        requires
        timeoutSeconds
        ;
      scripts = map (normalizeScript caseId) case.scripts;
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
