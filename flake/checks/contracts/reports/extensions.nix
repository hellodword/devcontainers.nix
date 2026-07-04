{
  lib,
  images,
  contractLib,
  ...
}:

let
  requiredProjectionTargets = [
    "/home/vscode/.vscode-server/extensions"
    "/home/vscode/.vscode-server-insiders/extensions"
    "/home/vscode/.vscode-remote/extensions"
  ];
  requiredLockKeys = [
    "ref"
    "sha256"
    "archiveName"
  ];
  projectionPrefix = "/usr/share/devcontainer/vscode/extensions/";
  lockComplete =
    extension:
    let
      sourceLock = extension.sourceLock or { };
    in
    lib.all (key: contractLib.nonEmptyString (sourceLock.${key} or null)) requiredLockKeys;
  perImage = lib.mapAttrsToList (
    name: image:
    let
      extensions = image.vscodeExtensions.extensions;
      extensionIds = map (extension: extension.id) extensions;
      profileExtensionIds = image.profiles.extensionIds;
      extensionById = lib.listToAttrs (
        map (extension: lib.nameValuePair extension.id extension) extensions
      );
      projectionExtensions = image.vscodeExtensions.projectionExtensions;
      projectionIds = map (extension: extension.id) projectionExtensions;
      projectionPaths = map (extension: extension.path) projectionExtensions;
      projectionTargets = image.vscodeExtensions.projectionTargets;
      missingProjectionTargets = builtins.filter (
        target: !(builtins.elem target projectionTargets)
      ) requiredProjectionTargets;
      checks = {
        validationNoNetwork =
          image.config.devcontainer.vscode.preinstall.validation.noNetworkDuringProjection;
        companionToolsProvided = image.profiles.report.validation.companionToolsProvidedByNix or false;
        noMissingCompanionTools = (image.profiles.report.validation.missingCompanionTools or [ ]) == [ ];
        projectionOnly = image.vscodeExtensions.artifacts.modes == [ "projection" ];
        projectionEnabled = image.vscodeExtensions.artifacts.projectionEnabled;
        archiveDisabled = !(image.vscodeExtensions.artifacts.archiveEnabled);
        projectionPath =
          image.vscodeExtensions.artifacts.projectionPath == "/usr/share/devcontainer/vscode/extensions";
        archivePath = image.vscodeExtensions.artifacts.archivePath == "/usr/share/devcontainer/vscode/vsix";
        extensionIdsMatchProfiles = contractLib.sameSet extensionIds profileExtensionIds;
        extensionIdsUnique = contractLib.duplicateValues extensionIds == [ ];
        extensionLocksComplete = lib.all lockComplete extensions;
        extensionSourcesFromNix = lib.all (
          extension: lib.hasPrefix "nix-vscode-extensions." extension.source
        ) extensions;
        extensionOriginsSingle = lib.all (
          extension: builtins.length (extension.origins or [ ]) == 1
        ) extensions;
        prettierOwnedByPrettierProfile = lib.all (
          extension:
          extension.id != "esbenp.prettier-vscode" || (extension.origins or [ ]) == [ "editor/prettier" ]
        ) extensions;
        projectionTargetsExpanded = lib.all (target: !(lib.hasInfix "$HOME" target)) projectionTargets;
        requiredProjectionTargetsPresent = missingProjectionTargets == [ ];
        projectionIdsMatchProfiles = contractLib.sameSet projectionIds profileExtensionIds;
        projectionIdsUnique = contractLib.duplicateValues projectionIds == [ ];
        projectionPathsUnique = contractLib.duplicateValues projectionPaths == [ ];
        projectionPathsUnderArtifactRoot = lib.all (
          extension:
          contractLib.nonEmptyString (extension.path or null) && lib.hasPrefix projectionPrefix extension.path
        ) projectionExtensions;
        projectionStrategyRecorded = lib.all (
          extension: contractLib.nonEmptyString (extension.projection or null)
        ) projectionExtensions;
        projectionRequiredMatches = lib.all (
          extension: ((extensionById.${extension.id} or { }).required or null) == extension.required
        ) projectionExtensions;
      };
    in
    {
      inherit name checks;
      details = {
        inherit
          extensionIds
          projectionIds
          missingProjectionTargets
          ;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-extensions = contractLib.mkAssertedJsonCheck "contracts-reports-extensions" [
    allValid
  ] { images = perImage; };
}
