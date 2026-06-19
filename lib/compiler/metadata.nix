{ lib }:
{ config, compiledEnv, compiledDockerAccess }:
let
  mergedContainerEnv = compiledEnv.containerEnv // compiledDockerAccess.containerEnv;

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
      dockerAccess = {
        enabled = compiledDockerAccess.enabled;
        defaultMode = compiledDockerAccess.defaultMode;
        privilege = compiledDockerAccess.privilegeReport;
        remoteTcpRequiresTls = compiledDockerAccess.modes.remoteTcpTls.enable;
        hostSocketMount = compiledDockerAccess.modes.hostSocket.mount;
        remoteTcpHost = compiledDockerAccess.modes.remoteTcpTls.host;
        remoteTcpCertMount = compiledDockerAccess.modes.remoteTcpTls.certMount;
      };
    };

  computedSnippet =
    {
      remoteUser = config.devcontainer.user.remoteUser;
      containerUser = config.devcontainer.user.containerUser;
      updateRemoteUserUID = config.devcontainer.user.updateRemoteUserUID;
      containerEnv = mergedContainerEnv;
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
    hasDockerAccessMetadata = mergedPreview ? dockerAccess;
  };
in
{
  label = snippets;
  mergedPreview = mergedPreview;
  schemaReport = schemaReport;
}
