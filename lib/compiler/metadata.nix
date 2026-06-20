{ lib }:
{ config, compiledEnv }:
let
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
        phase:
        builtins.any (task: task.phase == phase) (builtins.attrValues config.devcontainer.lifecycle.tasks)
      ) phases;
    in
    lib.foldl' lib.recursiveUpdate { } (map mkCommand enabledPhases);

  vscodeCustomization =
    lib.optionalAttrs
      ((config.devcontainer.vscode.extensions != [ ]) || (config.devcontainer.vscode.settings != { }))
      {
        customizations.vscode = {
          extensions = config.devcontainer.vscode.extensions;
          settings = config.devcontainer.vscode.settings;
        };
      };

  computedSnippet = {
    remoteUser = config.devcontainer.user.remoteUser;
    containerUser = config.devcontainer.user.containerUser;
    updateRemoteUserUID = config.devcontainer.user.updateRemoteUserUID;
    containerEnv = compiledEnv.containerEnv;
    remoteEnv = compiledEnv.remoteEnv;
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
    hasDockerMetadata = builtins.hasAttr dockerMetadataKey mergedPreview || mergedPreview ? mounts;
  };
in
{
  label = validatedSnippets;
  mergedPreview = mergedPreview;
  schemaReport = schemaReport;
}
