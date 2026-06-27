{
  pkgs,
  lib,
  runtimeHelpers,
  runtimeHelperList,
  nix2container,
  lockedNixpkgsSource ? null,
}:
{
  config,
  compiledEnvironment ? {
    systemPackages = [ ];
    pathsToLink = [
      "/bin"
      "/include"
      "/lib"
      "/lib64"
      "/libexec"
      "/share"
      "/etc"
    ];
    extraOutputsToInstall = [ ];
  },
  compiledEnv,
  compiledLibraries ? {
    imagePaths = [ ];
  },
  compiledShell ? {
    imagePaths = [ ];
  },
  compiledMetadata,
  compiledLifecycle,
  compiledVscodeExtensions,
  compiledFhsRuntime,
  compiledFilesystem,
  compiledFonts,
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

  usrMergePostBuild = ''
    merge_usr_dir() {
      local src="$1"
      local dst="$2"
      mkdir -p "$out/$dst"
      if [ -e "$out/$src" ] && [ ! -L "$out/$src" ]; then
        cp -a "$out/$src"/. "$out/$dst"/
        rm -rf "$out/$src"
      elif [ -L "$out/$src" ]; then
        rm "$out/$src"
      fi
      ln -s "$dst" "$out/$src"
    }

    mkdir -p \
      "$out/usr/bin" \
      "$out/usr/sbin" \
      "$out/usr/lib" \
      "$out/usr/lib64" \
      "$out/usr/libexec" \
      "$out/usr/include" \
      "$out/usr/share" \
      "$out/usr/local/bin" \
      "$out/usr/local/etc" \
      "$out/usr/local/include" \
      "$out/usr/local/lib" \
      "$out/usr/local/lib64" \
      "$out/usr/local/sbin" \
      "$out/usr/local/share" \
      "$out/usr/local/src"

    merge_usr_dir bin usr/bin
    merge_usr_dir sbin usr/sbin
    merge_usr_dir lib usr/lib
    merge_usr_dir lib64 usr/lib64
    merge_usr_dir libexec usr/libexec
    merge_usr_dir include usr/include
    merge_usr_dir share usr/share
  '';

  mkUsrMergedBuildEnv =
    args:
    pkgs.buildEnv (
      args
      // {
        postBuild = (args.postBuild or "") + "\n" + usrMergePostBuild;
      }
    );

  copyRoot = root: ''
    if [ -d ${root} ]; then
      (cd ${root} && find . -type d -print) | while IFS= read -r rel; do
        [ "$rel" = "." ] && continue
        if [ -L "$out/$rel" ] || { [ -e "$out/$rel" ] && [ ! -d "$out/$rel" ]; }; then
          rm -rf "$out/$rel"
        fi
      done
      cp -a --no-preserve=mode,ownership --remove-destination ${root}/. "$out/"
    fi
  '';
  lockedNixpkgsCommands = lib.optionalString (lockedNixpkgsSource != null) ''
    ln -sf ${lockedNixpkgsSource} "$out/usr/share/devcontainer/nixpkgs"
  '';

  entrypoint = runtimeHelpers."devcontainer-entrypoint".package;
  runtimeTools = map (helper: helper.package) (
    builtins.filter (helper: helper.installInImage) runtimeHelperList
  );

  runtimeRoot = mkUsrMergedBuildEnv {
    name = "${config.devcontainer.image.name}-runtime-root";
    paths = runtimeTools ++ compiledShell.imagePaths;
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
    ${lockedNixpkgsCommands}
    ${usrMergePostBuild}
  '';

  pathsForMembers =
    members: lib.unique (lib.concatMap (name: compiledGraph.rawNodes.${name}.paths) members);

  mkSemanticLayer =
    acc: layerReport:
    let
      paths = pathsForMembers layerReport.members;
      layerRoot = mkUsrMergedBuildEnv {
        name = "${config.devcontainer.image.name}-${layerReport.group}-root";
        inherit paths;
        pathsToLink = layerReport.build.pathsToLink;
        extraOutputsToInstall = compiledEnvironment.extraOutputsToInstall;
        ignoreCollisions = true;
      };
      rawLayer = nix2container.buildLayer {
        copyToRoot = layerRoot;
        layers = acc.layers;
        maxLayers = layerReport.build.maxLayers;
        metadata = {
          created_by = "devcontainers.nix semantic layer ${layerReport.group}";
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

  packageRoot = mkUsrMergedBuildEnv {
    name = "${config.devcontainer.image.name}-package-root";
    paths =
      compiledEnvironment.systemPackages
      ++ compiledLibraries.imagePaths
      ++ compiledShell.imagePaths
      ++ [ compiledFonts.root ]
      ++ runtimeTools;
    pathsToLink = compiledEnvironment.pathsToLink;
    extraOutputsToInstall = compiledEnvironment.extraOutputsToInstall;
    ignoreCollisions = true;
  };

  rootfs = pkgs.runCommand "${config.devcontainer.image.name}-rootfs" { } ''
    mkdir -p "$out"
    ${copyRoot packageRoot}
    ${copyRoot metadataRoot}
    ${copyRoot compiledFilesystem.root}
    ${usrMergePostBuild}
  '';

  labels = {
    "devcontainer.metadata" = builtins.toJSON compiledMetadata.label;
  };

  containerConfig = {
    User = config.devcontainer.user.containerUser;
    WorkingDir = "/workspaces";
    Env = lib.mapAttrsToList (name: value: "${name}=${value}") compiledEnv.containerEnv;
    Entrypoint = [ "/usr/bin/devcontainer-entrypoint" ];
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
