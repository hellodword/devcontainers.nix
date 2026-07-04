{
  lib,
  images,
  targets,
  contractLib,
  ...
}:

let
  perImage = lib.mapAttrsToList (
    name: image:
    let
      report = image.profiles.report;
      rootIdsFromProfiles = map (profile: profile.id) (report.rootEnabledProfiles or [ ]);
      effectiveIdsFromProfiles = map (profile: profile.id) (report.effectiveEnabledProfiles or [ ]);
      targetChecks = targets.imageTargets.${name}.checks or { };
      missingTargetProfiles = builtins.filter (profile: !(builtins.elem profile image.profiles.ids)) (
        targetChecks.requiredProfiles or [ ]
      );
      missingTargetCommands = builtins.filter (
        command: !(builtins.elem command image.profiles.providedCommands)
      ) (targetChecks.requiredCommands or [ ]);
      missingIncludeGraph = builtins.filter (
        profile: !(builtins.hasAttr profile (report.includeGraph or { }))
      ) image.profiles.ids;
      checks = {
        rootProfilesPresent = (report.rootEnabledProfiles or [ ]) != [ ];
        rootIdsMatch = (report.rootEnabledProfileIds or [ ]) == rootIdsFromProfiles;
        effectiveIdsMatchReport = (report.effectiveEnabledProfileIds or [ ]) == effectiveIdsFromProfiles;
        effectiveIdsMatchCompiler = (report.effectiveEnabledProfileIds or [ ]) == image.profiles.ids;
        includeGraphCoversEffectiveProfiles = missingIncludeGraph == [ ];
        packagesMatchCompiler = (report.packages or [ ]) == image.profiles.packageNames;
        commandsMatchCompiler = (report.provides.commands or [ ]) == image.profiles.providedCommands;
        extensionsMatchCompiler = (report.vscode.extensionIds or [ ]) == image.profiles.extensionIds;
        settingsMatchCompiler = (report.vscode.settings or { }) == image.profiles.settings;
        libraryPresetsMatchCompiler = (report.libraries.presets or [ ]) == image.profiles.libraryPresets;
        smokeCasesMatchCompiler = (report.tests.cases or [ ]) == image.profiles.testCaseIds;
        targetRequiredProfilesPresent = missingTargetProfiles == [ ];
        targetRequiredCommandsPresent = missingTargetCommands == [ ];
      };
    in
    {
      inherit name checks;
      details = {
        inherit
          missingIncludeGraph
          missingTargetProfiles
          missingTargetCommands
          ;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-profiles = contractLib.mkAssertedJsonCheck "contracts-reports-profiles" [
    allValid
  ] { images = perImage; };
}
