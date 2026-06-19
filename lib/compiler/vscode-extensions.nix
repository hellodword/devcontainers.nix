{ lib }:
{ config }:
let
  mkExtension =
    id:
    let
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
    in
    {
      inherit id native bucket;
      version = "pinned";
      source = "nix-vscode-extensions";
      path = "${config.devcontainer.vscode.preinstall.store.extensionsPath}/${pathSegment}";
      projection = if native then "copy-if-needed" else "symlink";
    };
in
{
  extensions = map mkExtension config.devcontainer.vscode.extensions;
  projectionTargets = config.devcontainer.vscode.preinstall.projection.targets;
}
