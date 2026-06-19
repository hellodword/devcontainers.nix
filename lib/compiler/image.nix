{ pkgs, lib, runtimePackages }:
{
  config,
  compiledEnv,
  compiledMetadata,
  compiledLifecycle,
  compiledVscodeExtensions,
  compiledFhsRuntime,
}:
let
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
        (extension: "mkdir -p .${extension.path}")
        compiledVscodeExtensions.extensions);
  mkManifestCommands =
    builtins.concatStringsSep "\n"
      (map
        (extension:
          let
            manifestFile =
              builtins.toFile
                "${builtins.replaceStrings [ "." ] [ "-" ] extension.id}-package.json"
                (builtins.toJSON {
                  name = extension.id;
                  publisher = builtins.head (lib.splitString "." extension.id);
                  version = "0.0.0";
                });
          in
          "cp ${manifestFile} .${extension.path}/package.json")
        compiledVscodeExtensions.extensions);
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

  entrypoint = runtimePackages."devcontainer-entrypoint";
  runtimeTools = [
    runtimePackages."devcontainer-task-runner"
    runtimePackages."vscode-extension-projector"
    runtimePackages."devcontainer-docker-access"
    runtimePackages.devpkg
    runtimePackages."devcontainer-image"
    entrypoint
  ];

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
        compiledEnv.containerEnv;
    Entrypoint = [ "/bin/devcontainer-entrypoint" ];
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
      mkdir -p etc usr/share/devcontainer/vsix
      cp ${osReleaseFile} etc/os-release
      ${mkDirCommands}
      ${mkManifestCommands}
      ${mkSymlinkCommands}
    '';
  };
in
{
  inherit rootfs oci;
}
