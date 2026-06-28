{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.devcontainer.vscode.preinstall = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };
    source = mkOption {
      type = types.str;
      default = "nix-vscode-extensions";
    };
    store = {
      extensionsPath = mkOption {
        type = types.str;
        default = "/usr/share/devcontainer/vscode/extensions";
      };
      vsixPath = mkOption {
        type = types.str;
        default = "/usr/share/devcontainer/vscode/vsix";
      };
      indexPath = mkOption {
        type = types.str;
        default = "/usr/share/devcontainer/vscode/extensions-index.json";
      };
    };
    projection = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      phase = mkOption {
        type = types.enum [
          "onCreate"
          "postCreate"
          "postStart"
          "postAttach"
        ];
        default = "postCreate";
      };
      mode = mkOption {
        type = types.str;
        default = "symlink-or-copy";
      };
      targets = mkOption {
        type = types.listOf types.str;
        default = [
          "${config.devcontainer.user.home}/.vscode-server/extensions"
          "${config.devcontainer.user.home}/.vscode-server-insiders/extensions"
          "${config.devcontainer.user.home}/.vscode-remote/extensions"
        ];
      };
    };
    validation = {
      nativeBinaries = mkOption {
        type = types.bool;
        default = true;
      };
      fhsRuntime = mkOption {
        type = types.bool;
        default = true;
      };
      noNetworkDuringProjection = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  config.devcontainer = {
    layers.bucketDefinitions."80-vscode-extensions-base" = {
      order = 29;
      owner = "editor/base";
      purpose = "Shared base VS Code extensions and extension metadata.";
    };

    profiles."editor/base" = {
      kind = "editor";
      group = "80-vscode-extensions-base";
      packages = [ ];
      priority = 80;
      stability = "stable";
      sharing = "global";
      securityClass = "trusted";
      composition.role = "bundle";
      includes = [
        "editor/core"
        "editor/prettier"
        "language/yaml"
        "editor/markdown-preview"
        "language/xml"
        "language/toml"
        "language/jinja"
        "language/protobuf"
        "editor/shellcheck"
      ];
    };
  };
}
