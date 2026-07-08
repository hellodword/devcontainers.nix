{
  pkgs,
  lib,
  images,
  targets,
  ...
}:

let
  policy = import ../../../images/contracts.nix;
  imageNames = builtins.attrNames images;
  targetNames = map (target: target.target) targets.imageTargetList;
  sortedTargetNames = lib.sort builtins.lessThan targetNames;
  uniqueTargetNames = lib.unique targetNames;
  nonEmptyString = value: builtins.isString value && value != "";

  imageContracts = lib.mapAttrsToList (
    name: image:
    let
      plan = image.reportData.imagePlan;
      smoke = image.reportData.smokePlan;
    in
    {
      inherit name;
      family = plan.family;
      publishRefs = plan.publishRefs;
      smokeCaseIds = smoke.caseIds;
    }
  ) images;

  targetRegistryContracts = map (
    target:
    let
      indexedTarget = targets.imageTargets.${target.target};
      imageConfig = images.${target.target}.config.devcontainer.image;
    in
    {
      name = target.target;
      registry = {
        inherit (target)
          family
          tags
          ;
        docsUseWhen = target.docs.useWhen or null;
      };
      compiled = {
        name = imageConfig.name;
        family = imageConfig.family;
        tags = imageConfig.tags;
      };
      indexedTargetMatches =
        indexedTarget.target == target.target
        && indexedTarget.family == target.family
        && indexedTarget.tags == target.tags
        && indexedTarget.docs.useWhen == target.docs.useWhen;
      docsValid = target ? docs && target.docs ? useWhen && nonEmptyString target.docs.useWhen;
      compiledMatches =
        imageConfig.name == target.target
        && imageConfig.family == target.family
        && imageConfig.tags == target.tags;
    }
  ) targets.imageTargetList;

  vscodeGuiE2e = import ../../../tests/e2e/vscode-gui.nix {
    inherit pkgs lib;
  };
  targetCiE2eSessions = lib.concatMap (target: target.ci.e2eSessions or [ ]) targets.imageTargetList;
  unknownTargetCiE2eSessions = builtins.filter (
    session: !(builtins.elem session vscodeGuiE2e.sessionNames)
  ) targetCiE2eSessions;

  actualRequiredTargets = map (target: target.target) (
    builtins.filter (target: target.checks.required or false) targets.imageTargetList
  );
  targetCheckContracts = map (
    target:
    let
      rootfsRequires = target.checks.rootfsRequires or [ ];
      requiredProfiles = target.checks.requiredProfiles or [ ];
      requiredCommands = target.checks.requiredCommands or [ ];
    in
    {
      name = target.target;
      inherit rootfsRequires requiredProfiles requiredCommands;
      rootfsRequiresValid = lib.all (path: nonEmptyString path && lib.hasPrefix "/" path) rootfsRequires;
      requiredProfilesValid = lib.all nonEmptyString requiredProfiles;
      requiredCommandsValid = lib.all (
        command: nonEmptyString command && builtins.match ".*/.*" command == null
      ) requiredCommands;
    }
  ) targets.imageTargetList;
  targetCheckMetadataValid = lib.all (
    contract:
    contract.rootfsRequiresValid && contract.requiredProfilesValid && contract.requiredCommandsValid
  ) targetCheckContracts;

  previousTargetPatternMatches = map (pattern: {
    inherit pattern;
    matches = builtins.filter (name: builtins.match pattern name != null) imageNames;
  }) policy.previousTargetPatterns;
  previousTargetPatternViolations = builtins.filter (
    contract: builtins.length contract.matches != 1
  ) previousTargetPatternMatches;
  previousTargets = lib.unique (
    lib.concatMap (contract: contract.matches) previousTargetPatternMatches
  );
  disallowedSuffixTargets = builtins.filter (
    name: lib.any (suffix: lib.hasSuffix suffix name) policy.disallowedTargetSuffixes
  ) imageNames;
  publishedExtensionOriginViolations = lib.concatMap (
    name:
    map
      (extension: {
        image = name;
        extension = extension.id;
        origins = extension.origins or [ ];
      })
      (
        builtins.filter (
          extension: builtins.length (extension.origins or [ ]) != 1
        ) images.${name}.vscodeExtensions.extensions
      )
  ) imageNames;
  prettierOriginViolations = lib.concatMap (
    name:
    map
      (extension: {
        image = name;
        origins = extension.origins or [ ];
      })
      (
        builtins.filter (
          extension:
          extension.id == "esbenp.prettier-vscode" && (extension.origins or [ ]) != [ "editor/prettier" ]
        ) images.${name}.vscodeExtensions.extensions
      )
  ) imageNames;
in
{
  contracts-image-targets =
    assert previousTargetPatternViolations == [ ];
    assert disallowedSuffixTargets == [ ];
    assert targetNames == targets.imageNames;
    assert sortedTargetNames == imageNames;
    assert builtins.length uniqueTargetNames == builtins.length targetNames;
    assert lib.all nonEmptyString targetNames;
    assert lib.all (contract: contract.indexedTargetMatches) targetRegistryContracts;
    assert lib.all (contract: contract.docsValid) targetRegistryContracts;
    assert lib.all (contract: contract.compiledMatches) targetRegistryContracts;
    assert unknownTargetCiE2eSessions == [ ];
    assert actualRequiredTargets == policy.requiredTargets;
    assert targetCheckMetadataValid;
    assert lib.all (contract: contract.publishRefs != [ ]) imageContracts;
    assert lib.all (contract: contract.smokeCaseIds != [ ]) imageContracts;
    assert publishedExtensionOriginViolations == [ ];
    assert prettierOriginViolations == [ ];
    pkgs.writeText "contracts-image-targets.json" (
      builtins.toJSON {
        previousTargets = previousTargets;
        previousTargetPatternMatches = previousTargetPatternMatches;
        requiredImageTargets = actualRequiredTargets;
        checkPolicy = targetCheckContracts;
        registry = targetRegistryContracts;
        ciE2eSessions = targetCiE2eSessions;
        images = imageContracts;
        extensionOriginViolations = publishedExtensionOriginViolations;
        prettierOriginViolations = prettierOriginViolations;
      }
    );
}
