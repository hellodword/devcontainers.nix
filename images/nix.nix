{ lib, pkgs, ... }:
{
  config = {
    environment.systemPackages = with pkgs; [
      nix
      nixd
      nil
      nixfmt
      alejandra
      statix
      deadnix
      treefmt
    ];

    devcontainer.image = {
      name = lib.mkOverride 1000 "nix";
      tags = lib.mkDefault [ "latest" ];
    };

    devcontainer.graph.nodes."runtime/nix" = {
      kind = "runtime";
      group = "10-nix-runtime";
      paths = [ pkgs.nix ];
      stability = "stable";
      sharing = "global";
      priority = 92;
      securityClass = "trusted";
    };

    devcontainer.graph.nodes."language/nix" = {
      kind = "language";
      group = "11-nix-language";
      paths = with pkgs; [
        nixd
        nil
        nixfmt
        alejandra
        statix
        deadnix
        treefmt
      ];
      stability = "stable";
      sharing = "global";
      priority = 90;
      securityClass = "trusted";
    };

    devcontainer.vscode.extensions = [
      "jnoortheen.nix-ide"
      "tamasfe.even-better-toml"
    ];

    devcontainer.vscode.settings = {
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nixd";
      "nix.serverSettings" = {
        "nixd" = {
          "formatting" = {
            "command" = [ "nixfmt" ];
          };
        };
      };
      "nix.formatterPath" = "nixfmt";
    };

    devcontainer.tests.smoke = [
      {
        name = "nix-version";
        command = [
          "nix"
          "--version"
        ];
      }
      {
        name = "nixd-version";
        command = [
          "nixd"
          "--version"
        ];
      }
      {
        name = "nix-language";
        command = [
          "bash"
          "-lc"
          "nixfmt --version && alejandra --version && statix --help >/dev/null && deadnix --version"
        ];
      }
      {
        name = "extension-index";
        command = [
          "bash"
          "-lc"
          "test -f /usr/share/devcontainer/vscode/extensions-index.json"
        ];
      }
      {
        name = "task-runner-list";
        command = [
          "devcontainer-task-runner"
          "list"
        ];
      }
      {
        name = "devpkg-list";
        command = [
          "bash"
          "-lc"
          "devpkg list >/dev/null"
        ];
      }
    ];
  };
}
