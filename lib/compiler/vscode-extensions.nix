{ lib }:
{ config }:
let
  hashString = value: builtins.hashString "sha256" value;
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
      publisher = builtins.head parts;
      name = lib.concatStringsSep "." (builtins.tail parts);
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
      pathSegment = builtins.replaceStrings [ "." ] [ "-" ] id;
      vsixName = "${pathSegment}.vsix";
      manifestJson =
        builtins.toJSON {
          inherit name publisher;
          version = "0.0.0";
          engines.vscode = "^1.90.0";
        };
      vsixPlaceholder = "placeholder vsix for ${id}\n";
      sourceLock =
        let
          lockRef = "nix-vscode-extensions:${id}:pinned";
        in
        {
          ref = lockRef;
          sha256 = hashString lockRef;
          manifestSha256 = hashString manifestJson;
          vsixSha256 = hashString vsixPlaceholder;
        };
    in
    {
      inherit id native bucket publisher name;
      version = "pinned";
      source = "nix-vscode-extensions";
      pathSegment = pathSegment;
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
{
  extensions = map mkExtension config.devcontainer.vscode.extensions;
  projectionTargets = config.devcontainer.vscode.preinstall.projection.targets;
}
