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
    layers.bucketDefinitions."vscode-extensions-base" = {
      order = 60000;
      owner = "editor/base";
      purpose = "Shared base VS Code extensions and extension metadata.";
    };

    profiles."editor/base" = {
      kind = "editor";
      group = "vscode-extensions-base";
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
        "editor/vscode-machine-settings-smoke"
      ];
    };

    profiles."editor/vscode-machine-settings-smoke" = {
      kind = "editor";
      group = "vscode-extensions-base";
      packages = [ ];
      priority = 79;
      stability = "stable";
      sharing = "global";
      securityClass = "trusted";
      composition.role = "leaf";
      tests.cases."editor.vscode-machine-settings-readonly" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "editor"
          "vscode"
        ];
        command = [
          "bash"
          "-lc"
          (lib.concatStringsSep " " [
            ''for root in "$HOME/.vscode-server" "$HOME/.vscode-server-insiders" "$HOME/.vscode-remote"; do''
            ''settings="$root/data/Machine/settings.json";''
            ''test -f "$settings" || exit 1;''
            ''test -r "$settings" || exit 1;''
            ''test ! -w "$settings" || exit 1;''
            ''if printf '%s\n' '{}' >"$settings" 2>/dev/null; then exit 1; fi;''
            "done"
          ])
        ];
      };
    };
  };
}
