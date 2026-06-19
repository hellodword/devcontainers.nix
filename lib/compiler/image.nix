{
  pkgs,
  lib,
  runtimePackages,
  nix2container,
}:
{
  config,
  compiledEnv,
  compiledMetadata,
  compiledLifecycle,
  compiledVscodeExtensions,
  compiledFhsRuntime,
  compiledFilesystem,
  compiledGraph,
  compiledLayers,
}:
let
  renderJson = value: builtins.toFile "payload.json" (builtins.toJSON value);

  tasksFile = renderJson { tasks = compiledLifecycle.tasks; };
  extensionsFile = renderJson {
    extensions = compiledVscodeExtensions.extensions;
    projectionTargets = compiledVscodeExtensions.projectionTargets;
  };

  mkDirCommands = builtins.concatStringsSep "\n" (
    map (extension: ''
      mkdir -p "$out$(dirname ${extension.path})"
      mkdir -p "$out$(dirname ${extension.vsixPath})"
    '') compiledVscodeExtensions.imageExtensions
  );
  mkExtensionCommands = builtins.concatStringsSep "\n" (
    map (extension: ''
      cp -a ${extension.sourcePath} "$out${extension.path}"
      cp ${extension.archivePath} "$out${extension.vsixPath}"
    '') compiledVscodeExtensions.imageExtensions
  );
  mkSymlinkCommands = builtins.concatStringsSep "\n" (
    map (
      link:
      let
        targetDir = builtins.dirOf link.target;
      in
      ''
        mkdir -p "$out${targetDir}"
        ln -sf ${link.source} "$out${link.target}"
      ''
    ) compiledFhsRuntime.symlinks
  );

  localBinCommands = ''
    mkdir -p "$out/usr/local/bin"
    ln -sf /bin/devcontainer-entrypoint "$out/usr/local/bin/devcontainer-entrypoint"
  '';

  entrypoint = runtimePackages."devcontainer-entrypoint";
  runtimeTools = [
    runtimePackages."devcontainer-task-runner"
    runtimePackages."vscode-extension-projector"
    runtimePackages.devpkg
    runtimePackages."devcontainer-image"
    entrypoint
  ];

  runtimeRoot = pkgs.buildEnv {
    name = "${config.devcontainer.image.name}-runtime-root";
    paths = runtimeTools;
    pathsToLink = [
      "/bin"
      "/share"
    ];
  };

  metadataRoot = pkgs.runCommand "${config.devcontainer.image.name}-metadata-root" { } ''
    mkdir -p "$out/usr/share/devcontainer/vscode" "$out/usr/share/devcontainer"
    cp ${tasksFile} "$out/usr/share/devcontainer/tasks.json"
    cp ${extensionsFile} "$out/usr/share/devcontainer/vscode/extensions-index.json"
    mkdir -p "$out/usr/share/devcontainer/vscode/vsix"
    ${mkDirCommands}
    ${mkExtensionCommands}
    ${mkSymlinkCommands}
    ${localBinCommands}
  '';

  pathsForMembers =
    members: lib.unique (lib.concatMap (name: config.devcontainer.graph.nodes.${name}.paths) members);

  mkSemanticLayer =
    acc: layerReport:
    let
      paths = pathsForMembers layerReport.members;
      layerRoot = pkgs.buildEnv {
        name = "${config.devcontainer.image.name}-${layerReport.group}-root";
        inherit paths;
        pathsToLink = layerReport.build.pathsToLink;
        ignoreCollisions = true;
      };
      rawLayer = nix2container.buildLayer {
        copyToRoot = layerRoot;
        layers = acc.layers;
        maxLayers = layerReport.build.maxLayers;
        metadata = {
          created_by = "devcontainers.nix2 semantic layer ${layerReport.group}";
          comment = builtins.concatStringsSep "," layerReport.members;
        };
      };
      layer = rawLayer // {
        # We pass every prior semantic layer explicitly. Keeping nix2container's
        # transitive nestedLayers here makes buildImage expand duplicates.
        nestedLayers = [ ];
      };
    in
    {
      layers = acc.layers ++ [ layer ];
      roots = acc.roots ++ [ layerRoot ];
    };

  semanticLayerState = lib.foldl' mkSemanticLayer {
    layers = [ ];
    roots = [ ];
  } compiledLayers.layers;

  rootfs = pkgs.buildEnv {
    name = "${config.devcontainer.image.name}-rootfs";
    paths = config.devcontainer.packages ++ runtimeTools;
    pathsToLink = [
      "/bin"
      "/lib"
      "/lib64"
      "/share"
      "/etc"
    ];
    ignoreCollisions = true;
  };

  labels = {
    "devcontainer.metadata" = builtins.toJSON compiledMetadata.label;
  };

  containerConfig = {
    User = config.devcontainer.user.containerUser;
    WorkingDir = "/workspaces";
    Env = lib.mapAttrsToList (name: value: "${name}=${value}") compiledEnv.containerEnv;
    Entrypoint = [ "/usr/local/bin/devcontainer-entrypoint" ];
    Cmd = [
      "sleep"
      "infinity"
    ];
    Labels = labels;
  };

  imageTag =
    if config.devcontainer.image.tags == [ ] then
      "latest"
    else
      builtins.head config.devcontainer.image.tags;

  image = nix2container.buildImage {
    name = "ghcr.io/hellodword/devcontainers-${config.devcontainer.image.family}";
    tag = imageTag;
    arch = "amd64";
    initializeNixDatabase = true;
    nixUid = config.devcontainer.user.uid;
    nixGid = config.devcontainer.user.gid;
    layers = semanticLayerState.layers;
    copyToRoot = [
      runtimeRoot
      metadataRoot
      compiledFilesystem.root
    ];
    perms = compiledFilesystem.perms;
    maxLayers = 4;
    config = containerConfig;
    meta = {
      inherit (compiledGraph) groups;
      semanticLayerCount = builtins.length semanticLayerState.layers;
    };
  };
in
{
  inherit rootfs;
  oci = image;
  copyToDockerDaemon = image.copyToDockerDaemon;
}
