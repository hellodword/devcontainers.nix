{ pkgs, lib, runtimePackages }:
{
  config,
  compiledEnv,
  compiledMetadata,
  compiledLifecycle,
  compiledVscodeExtensions,
  compiledDockerAccess,
  compiledFhsRuntime,
}:
let
  mergedContainerEnv = compiledEnv.containerEnv // compiledDockerAccess.containerEnv;

  renderJson = value: builtins.toFile "payload.json" (builtins.toJSON value);

  tasksFile = renderJson { tasks = compiledLifecycle.tasks; };
  extensionsFile =
    renderJson {
      extensions = compiledVscodeExtensions.extensions;
      projectionTargets = compiledVscodeExtensions.projectionTargets;
    };
  osReleaseFile = builtins.toFile "os-release" compiledFhsRuntime.osReleaseText;

  mkDirCommands =
    builtins.concatStringsSep "\n"
      (map
        (extension:
          ''
            mkdir -p .$(dirname ${extension.path})
            mkdir -p .$(dirname ${extension.vsixPath})
          '')
        compiledVscodeExtensions.imageExtensions);
  mkExtensionCommands =
    builtins.concatStringsSep "\n"
      (map
        (extension:
          ''
            cp -a ${extension.sourcePath} .${extension.path}
            cp ${extension.archivePath} .${extension.vsixPath}
          '')
        compiledVscodeExtensions.imageExtensions);
  mkSymlinkCommands =
    builtins.concatStringsSep "\n"
      (map
        (link:
          let
            targetDir = builtins.dirOf link.target;
          in
          ''
            mkdir -p .${targetDir}
            ln -sf ${link.source} .${link.target}
          '')
        compiledFhsRuntime.symlinks);
  localBinCommands = ''
    mkdir -p ./usr/local/bin
    ln -sf /bin/devcontainer-entrypoint ./usr/local/bin/devcontainer-entrypoint
  '';

  entrypoint = runtimePackages."devcontainer-entrypoint";
  runtimeTools =
    [
      runtimePackages."devcontainer-task-runner"
      runtimePackages."vscode-extension-projector"
      runtimePackages.devpkg
      runtimePackages."devcontainer-image"
      entrypoint
    ]
    ++ lib.optional compiledDockerAccess.enabled runtimePackages."devcontainer-docker-access";

  rootfs = pkgs.buildEnv {
    name = "${config.devcontainer.image.name}-rootfs";
    paths = config.devcontainer.packages ++ runtimeTools;
    pathsToLink = [
      "/bin"
      "/share"
    ];
  };

  labels = {
    "devcontainer.metadata" = builtins.toJSON compiledMetadata.label;
  };

  containerConfig = {
    Env =
      lib.mapAttrsToList
        (name: value: "${name}=${value}")
        mergedContainerEnv;
    Entrypoint = [ "/usr/local/bin/devcontainer-entrypoint" ];
    Cmd = [ "sleep" "infinity" ];
    Labels = labels;
  };

  oci = pkgs.dockerTools.buildLayeredImage {
    name = "devcontainer-${config.devcontainer.image.name}";
    tag =
      if config.devcontainer.image.tags == [ ] then
        "latest"
      else
        builtins.head config.devcontainer.image.tags;
    contents = [ rootfs ];
    config = containerConfig;
    extraCommands = ''
      mkdir -p usr/share/devcontainer/vscode usr/share/devcontainer
      cp ${tasksFile} usr/share/devcontainer/tasks.json
      cp ${extensionsFile} usr/share/devcontainer/vscode/extensions-index.json
      mkdir -p etc usr/share/devcontainer/vscode/vsix
      cp ${osReleaseFile} etc/os-release
      ${mkDirCommands}
      ${mkExtensionCommands}
      ${mkSymlinkCommands}
      ${localBinCommands}
    '';
  };
in
{
  inherit rootfs oci;
}
