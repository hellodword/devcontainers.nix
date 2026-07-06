{ lib }:
{
  config,
  compiledEnv,
  compiledProfiles ? {
    extensionIds = [ ];
    settings = { };
    tasks = { };
  },
}:
let
  protectedWorkspaceConfigMount = "source=\${localWorkspaceFolder}/.devcontainer,target=/workspaces/\${localWorkspaceFolderBasename}/.devcontainer,type=bind,readonly";
  allTasks = compiledProfiles.tasks // config.devcontainer.lifecycle.tasks;
  lifecycleCommands =
    let
      phases = [
        "onCreate"
        "postCreate"
        "postStart"
        "postAttach"
      ];
      mkCommand = phase: {
        "${phase}Command" = {
          "devcontainer-tasks" = "devcontainer-task-runner run ${phase}";
        };
      };
      enabledPhases = lib.filter (
        phase: builtins.any (task: task.phase == phase) (builtins.attrValues allTasks)
      ) phases;
    in
    lib.foldl' lib.recursiveUpdate { } (map mkCommand enabledPhases);

  vscodeCustomization = lib.optionalAttrs (compiledProfiles.extensionIds != [ ]) {
    customizations.vscode = {
      extensions = compiledProfiles.extensionIds;
    };
  };
  workspace = compiledEnv.workspace or { };
  workspaceLateBound = workspace.lateBound or false;
  workspaceMetadataValue = workspace.metadataValue or "\${containerWorkspaceFolder}";
  workspaceValueForMetadata =
    value:
    if !workspaceLateBound || !builtins.isString value then
      value
    else if value == "$WORKSPACE" || value == "\${WORKSPACE}" then
      workspaceMetadataValue
    else if lib.hasPrefix "$WORKSPACE/" value then
      workspaceMetadataValue + "/" + lib.removePrefix "$WORKSPACE/" value
    else if lib.hasPrefix "\${WORKSPACE}/" value then
      workspaceMetadataValue + "/" + lib.removePrefix "\${WORKSPACE}/" value
    else
      value;
  workspaceMetadataEnv = lib.optionalAttrs workspaceLateBound {
    WORKSPACE = workspaceMetadataValue;
  };
  containerEnv =
    (lib.mapAttrs (_: workspaceValueForMetadata) (removeAttrs compiledEnv.containerEnv [ "PATH" ]))
    // (lib.mapAttrs (_: workspaceValueForMetadata) (compiledEnv.lateBoundContainerEnv or { }))
    // workspaceMetadataEnv;
  remoteEnv = lib.mapAttrs (_: workspaceValueForMetadata) compiledEnv.remoteEnv;

  computedSnippet = {
    remoteUser = config.devcontainer.user.remoteUser;
    containerUser = config.devcontainer.user.containerUser;
    updateRemoteUserUID = config.devcontainer.user.updateRemoteUserUID;
    mounts = [ protectedWorkspaceConfigMount ];
    inherit containerEnv remoteEnv;
  }
  // lib.optionalAttrs config.devcontainer.gui.forwarding.enable {
    userEnvProbe = "loginInteractiveShell";
  }
  // lifecycleCommands
  // vscodeCustomization;

  snippets = config.devcontainer.metadata.snippets ++ [ computedSnippet ];
  invalidUserSnippet = lib.findFirst (
    snippet:
    (snippet ? remoteUser && snippet.remoteUser != "vscode")
    || (snippet ? containerUser && snippet.containerUser != "vscode")
    || (snippet ? updateRemoteUserUID && snippet.updateRemoteUserUID == true)
  ) null config.devcontainer.metadata.snippets;
  validatedSnippets =
    if invalidUserSnippet != null then
      builtins.throw "devcontainer metadata may not override the user. Remove remoteUser/containerUser/updateRemoteUserUID or keep remoteUser/containerUser as vscode and updateRemoteUserUID as false."
    else
      snippets;
  mergedPreview = lib.foldl' lib.recursiveUpdate { } validatedSnippets;
  dockerMetadataKey = "docker" + "Access";
  labelMounts = lib.concatMap (snippet: snippet.mounts or [ ]) validatedSnippets;
  protectedWorkspaceConfigMounts = builtins.filter (
    mount: mount == protectedWorkspaceConfigMount
  ) labelMounts;
  unexpectedMounts = builtins.filter (mount: mount != protectedWorkspaceConfigMount) labelMounts;
  hasDockerAccess = builtins.any (
    snippet: builtins.hasAttr dockerMetadataKey snippet
  ) validatedSnippets;
  schemaReport = {
    snippetCount = builtins.length validatedSnippets;
    hasRemoteUser = mergedPreview ? remoteUser;
    hasLifecycle = builtins.any (name: mergedPreview ? "${name}Command") [
      "onCreate"
      "postCreate"
      "postStart"
      "postAttach"
    ];
    hasVscodeCustomizations = mergedPreview ? customizations;
    hasWorkspaceConfigProtection = builtins.length protectedWorkspaceConfigMounts == 1;
    protectedWorkspaceConfigMountCount = builtins.length protectedWorkspaceConfigMounts;
    hasDockerMetadata = hasDockerAccess || unexpectedMounts != [ ];
    unexpectedMounts = unexpectedMounts;
  };
in
{
  label = validatedSnippets;
  mergedPreview = mergedPreview;
  workspaceConfigProtection = {
    mount = protectedWorkspaceConfigMount;
    source = "\${localWorkspaceFolder}/.devcontainer";
    target = "/workspaces/\${localWorkspaceFolderBasename}/.devcontainer";
  };
  schemaReport = schemaReport;
}
