{
  lib,
  pkgs,
}:
{ config }:
let
  hashString = value: builtins.hashString "sha256" value;
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  extensionSets = {
    vscode-marketplace-release = pkgs.vscode-marketplace-release;
    open-vsx-release = pkgs.open-vsx-release;
  };
  attrForId =
    id:
    let
      parts = lib.splitString "." id;
      publisher = lib.toLower (builtins.head parts);
      name = lib.toLower (lib.concatStringsSep "." (builtins.tail parts));
    in
    [
      publisher
      name
    ];
  resolveExtension =
    id:
    let
      attrPath = attrForId id;
      marketplace = lib.attrByPath attrPath null extensionSets.vscode-marketplace-release;
      openVsx = lib.attrByPath attrPath null extensionSets.open-vsx-release;
    in
    if marketplace != null then
      {
        package = marketplace;
        source = "nix-vscode-extensions.vscode-marketplace-release";
      }
    else if openVsx != null then
      {
        package = openVsx;
        source = "nix-vscode-extensions.open-vsx-release";
      }
    else
      builtins.throw "VS Code extension ${id} was not found in nix-vscode-extensions release sets";
  sourceRefFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
      urls = if srcDrv != null && srcDrv ? urls then srcDrv.urls else [ ];
    in
    if urls != [ ] then
      builtins.head urls
    else
      "nix-store:${pathString (extensionPackage.src or extensionPackage)}";
  sourceHashFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
    in
    if srcDrv != null && srcDrv ? outputHash then
      srcDrv.outputHash
    else
      hashString (pathString (extensionPackage.src or extensionPackage));
  sourceArchiveNameFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
    in
    if srcDrv != null && srcDrv ? name then
      srcDrv.name
    else
      builtins.baseNameOf (pathString (extensionPackage.src or extensionPackage));
  companionToolsFor =
    id:
    if lib.hasPrefix "jnoortheen.nix-ide" id then
      [
        "nixd"
        "nixfmt"
      ]
    else if lib.hasPrefix "ms-python.python" id || lib.hasPrefix "ms-python.vscode-pylance" id then
      [
        "python"
        "ruff"
      ]
    else if lib.hasPrefix "charliermarsh.ruff" id then
      [ "ruff" ]
    else if
      lib.hasPrefix "dbaeumer.vscode-eslint" id
      || lib.hasPrefix "esbenp.prettier-vscode" id
      || lib.hasPrefix "vue.volar" id
    then
      [
        "node"
        "typescript-language-server"
        "eslint"
        "prettier"
      ]
    else if lib.hasPrefix "golang.go" id then
      [
        "go"
        "gopls"
        "dlv"
      ]
    else if lib.hasPrefix "rust-lang.rust-analyzer" id then
      [
        "rust-analyzer"
        "cargo"
        "clippy-driver"
      ]
    else if lib.hasPrefix "dart-code." id then
      [
        "flutter"
        "dart"
      ]
    else
      [ ];
  mkExtension =
    id:
    let
      resolved = resolveExtension id;
      extensionPackage = resolved.package;
      passthru = extensionPackage.passthru or { };
      parts = lib.splitString "." id;
      requestedPublisher = builtins.head parts;
      requestedName = lib.concatStringsSep "." (builtins.tail parts);
      publisher =
        if passthru ? vscodeExtPublisher then passthru.vscodeExtPublisher else requestedPublisher;
      name = if passthru ? vscodeExtName then passthru.vscodeExtName else requestedName;
      uniqueId =
        if passthru ? vscodeExtUniqueId then passthru.vscodeExtUniqueId else "${publisher}.${name}";
      native = lib.any (prefix: lib.hasPrefix prefix id) [
        "ms-python."
        "golang."
        "rust-lang."
        "dart-code."
      ];
      bucket =
        if lib.hasPrefix "jnoortheen." id then
          "81-vscode-extensions-nix"
        else if lib.hasPrefix "ms-python." id || lib.hasPrefix "charliermarsh." id then
          "82-vscode-extensions-python"
        else if lib.hasPrefix "dbaeumer." id || lib.hasPrefix "esbenp." id || lib.hasPrefix "vue." id then
          "83-vscode-extensions-nodejs"
        else if lib.hasPrefix "golang." id then
          "84-vscode-extensions-go"
        else if lib.hasPrefix "rust-lang." id then
          "85-vscode-extensions-rust"
        else if lib.hasPrefix "dart-code." id then
          "86-vscode-extensions-flutter"
        else
          "80-vscode-extensions-base";
      pathSegment = uniqueId;
      vsixName = "${builtins.replaceStrings [ "." ] [ "-" ] uniqueId}.vsix";
      extensionVersion = extensionPackage.version or "unknown";
      sourceRef = sourceRefFor extensionPackage;
      sourceHash = sourceHashFor extensionPackage;
      sourceLock = {
        ref = sourceRef;
        sha256 = sourceHash;
        manifestSha256 = hashString "${uniqueId}:${extensionVersion}:${sourceHash}:manifest";
        vsixSha256 = sourceHash;
        archiveName = sourceArchiveNameFor extensionPackage;
      };
      public = {
        inherit
          id
          native
          bucket
          publisher
          name
          uniqueId
          ;
        version = extensionVersion;
        source = resolved.source;
        path = "${config.devcontainer.vscode.preinstall.store.extensionsPath}/${pathSegment}";
        vsixPath = "${config.devcontainer.vscode.preinstall.store.vsixPath}/${vsixName}";
        projection = if native then "copy-if-needed" else "symlink";
        companionTools = companionToolsFor id;
        sourceLock = sourceLock;
        validation = {
          nativeBinaries = native;
          fhsRuntime = config.devcontainer.vscode.preinstall.validation.fhsRuntime;
          noNetworkDuringProjection =
            config.devcontainer.vscode.preinstall.validation.noNetworkDuringProjection;
          strategy = if native then "copy-if-needed-with-fhs" else "symlink";
        };
      };
    in
    {
      inherit public;
      image = {
        inherit (public) id path vsixPath;
        sourcePath = "${extensionPackage}/share/vscode/extensions/${uniqueId}";
        archivePath = extensionPackage.src or extensionPackage;
      };
    };
  compiledExtensions = map mkExtension config.devcontainer.vscode.extensions;
in
{
  extensions = map (extension: extension.public) compiledExtensions;
  imageExtensions = map (extension: extension.image) compiledExtensions;
  projectionTargets = config.devcontainer.vscode.preinstall.projection.targets;
}
