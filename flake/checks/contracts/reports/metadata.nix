{
  lib,
  images,
  contractLib,
  ...
}:

let
  perImage = lib.mapAttrsToList (
    name: image:
    let
      metadata = image.metadata;
      preview = metadata.mergedPreview;
      previewEnv = preview.containerEnv or { };
      previewMounts = preview.mounts or [ ];
      schema = metadata.schemaReport;
      checks = {
        labelIsArray = builtins.isList metadata.label;
        hasRemoteUser = schema.hasRemoteUser or false;
        hasLifecycle = schema.hasLifecycle or false;
        hasVscodeCustomizations = schema.hasVscodeCustomizations or false;
        noDockerMetadata = !(schema.hasDockerMetadata or true);
        workspaceConfigProtection = schema.hasWorkspaceConfigProtection or false;
        protectedMountInPreview = builtins.elem metadata.workspaceConfigProtection.mount previewMounts;
        remoteUser = (preview.remoteUser or null) == "vscode";
        containerUser = (preview.containerUser or null) == "vscode";
        updateRemoteUserUid = (preview.updateRemoteUserUID or null) == false;
        noPathInContainerEnv = !(builtins.hasAttr "PATH" previewEnv);
        noRuntimeDirInContainerEnv = !(builtins.hasAttr "XDG_RUNTIME_DIR" previewEnv);
        editorMatchesEnv = (previewEnv.EDITOR or null) == (image.env.containerEnv.EDITOR or null);
        nixLdMatchesEnv = (previewEnv.NIX_LD or null) == (image.env.containerEnv.NIX_LD or null);
      };
    in
    {
      inherit name checks;
      details = {
        snippetCount = schema.snippetCount or null;
        mount = metadata.workspaceConfigProtection.mount;
        unexpectedMounts = schema.unexpectedMounts or [ ];
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-metadata = contractLib.mkAssertedJsonCheck "contracts-reports-metadata" [
    allValid
  ] { images = perImage; };
}
