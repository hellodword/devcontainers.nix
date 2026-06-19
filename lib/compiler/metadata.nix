{ lib }:
{ config, compiledEnv }:
let
  lifecycleCommands =
    let
      phases = [ "onCreate" "postCreate" "postStart" "postAttach" ];
      mkCommand = phase: {
        "${phase}Command" = {
          "devcontainer-tasks" = "devcontainer-task-runner run ${phase}";
        };
      };
      enabledPhases =
        lib.filter
          (phase:
            builtins.any
              (task: task.phase == phase)
              (builtins.attrValues config.devcontainer.lifecycle.tasks))
          phases;
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

  dockerMetadata =
    lib.optionalAttrs config.devcontainer.dockerAccess.enable {
      mounts = config.devcontainer.dockerAccess.mounts;
      containerEnv = config.devcontainer.dockerAccess.containerEnv;
    };

  computedSnippet =
    {
      remoteUser = config.devcontainer.user.remoteUser;
      containerUser = config.devcontainer.user.containerUser;
      updateRemoteUserUID = config.devcontainer.user.updateRemoteUserUID;
      containerEnv = compiledEnv.containerEnv;
      remoteEnv = compiledEnv.remoteEnv;
    }
    // lifecycleCommands
    // vscodeCustomization
    // dockerMetadata;

  snippets = config.devcontainer.metadata.snippets ++ [ computedSnippet ];
  mergedPreview = lib.foldl' lib.recursiveUpdate { } snippets;
  schemaReport = {
    snippetCount = builtins.length snippets;
    hasRemoteUser = mergedPreview ? remoteUser;
    hasLifecycle = builtins.any
      (name: mergedPreview ? "${name}Command")
      [ "onCreate" "postCreate" "postStart" "postAttach" ];
    hasVscodeCustomizations = mergedPreview ? customizations;
    dockerAccessEnabled = config.devcontainer.dockerAccess.enable;
  };
in
{
  label = snippets;
  mergedPreview = mergedPreview;
  schemaReport = schemaReport;
}
