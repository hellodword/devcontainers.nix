{ lib, pkgs }:
{ config }:
let
  hashString = value: builtins.hashString "sha256" value;
  sourceRefFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
      urls = if srcDrv != null && srcDrv ? urls then srcDrv.urls else [ ];
    in
    if urls != [ ] then
      builtins.head urls
    else
      "nix-store:${toString (extensionPackage.src or extensionPackage)}";
  sourceHashFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
    in
    if srcDrv != null && srcDrv ? outputHash then
      srcDrv.outputHash
    else
      hashString (toString (extensionPackage.src or extensionPackage));
  sourceArchiveNameFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
    in
    if srcDrv != null && srcDrv ? name then
      srcDrv.name
    else
      builtins.baseNameOf (toString (extensionPackage.src or extensionPackage));
  companionToolsFor =
    id:
    if lib.hasPrefix "jnoortheen.nix-ide" id then
      [ "nixd" "nixfmt" ]
    else if lib.hasPrefix "ms-python.python" id || lib.hasPrefix "ms-python.vscode-pylance" id then
      [ "python" "ruff" ]
    else if lib.hasPrefix "charliermarsh.ruff" id then
      [ "ruff" ]
    else if lib.hasPrefix "dbaeumer.vscode-eslint" id || lib.hasPrefix "esbenp.prettier-vscode" id || lib.hasPrefix "vue.volar" id then
      [ "node" "typescript-language-server" "eslint" "prettier" ]
    else if lib.hasPrefix "golang.go" id then
      [ "go" "gopls" "dlv" ]
    else if lib.hasPrefix "rust-lang.rust-analyzer" id then
      [ "rust-analyzer" "cargo" "clippy-driver" ]
    else if lib.hasPrefix "dart-code." id then
      [ "flutter" "dart" ]
    else
      [ ];
  mkExtension =
    id:
    let
      parts = lib.splitString "." id;
      requestedPublisher = builtins.head parts;
      requestedName = lib.concatStringsSep "." (builtins.tail parts);
      extensionPackage = lib.attrByPath parts null pkgs.vscode-extensions;
      publisher =
        if extensionPackage != null && extensionPackage.passthru ? vscodeExtPublisher then
          extensionPackage.passthru.vscodeExtPublisher
        else
          requestedPublisher;
      name =
        if extensionPackage != null && extensionPackage.passthru ? vscodeExtName then
          extensionPackage.passthru.vscodeExtName
        else
          requestedName;
      uniqueId =
        if extensionPackage != null && extensionPackage.passthru ? vscodeExtUniqueId then
          extensionPackage.passthru.vscodeExtUniqueId
        else
          "${publisher}.${name}";
      native =
        lib.any
          (prefix: lib.hasPrefix prefix id)
          [
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
      extensionVersion =
        if extensionPackage != null && extensionPackage ? version then
          extensionPackage.version
        else
          "unknown";
      sourceRef = sourceRefFor extensionPackage;
      sourceHash = sourceHashFor extensionPackage;
      sourceLock =
        {
          ref = sourceRef;
          sha256 = sourceHash;
          manifestSha256 = hashString "${uniqueId}:${extensionVersion}:${sourceHash}:manifest";
          vsixSha256 = sourceHash;
          archiveName = sourceArchiveNameFor extensionPackage;
        };
      public =
        {
          inherit id native bucket publisher name uniqueId;
          version = extensionVersion;
          source = "nixpkgs.vscode-extensions";
          path = "${config.devcontainer.vscode.preinstall.store.extensionsPath}/${pathSegment}";
          vsixPath = "${config.devcontainer.vscode.preinstall.store.vsixPath}/${vsixName}";
          projection = if native then "copy-if-needed" else "symlink";
          companionTools = companionToolsFor id;
          sourceLock = sourceLock;
          validation = {
            nativeBinaries = native;
            fhsRuntime = config.devcontainer.vscode.preinstall.validation.fhsRuntime;
            noNetworkDuringProjection = config.devcontainer.vscode.preinstall.validation.noNetworkDuringProjection;
            strategy = if native then "copy-if-needed-with-fhs" else "symlink";
          };
        };
    in
    assert extensionPackage != null;
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
