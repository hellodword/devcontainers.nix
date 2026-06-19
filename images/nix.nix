{ lib, pkgs, ... }:
{
  config.devcontainer = {
    image = {
      name = lib.mkOverride 1000 "nix";
      tags = lib.mkDefault [ "latest" ];
    };

    packages = with pkgs; [
      nix
      nixd
      nil
      nixfmt
      alejandra
      statix
      deadnix
      treefmt
    ];

    graph.nodes."runtime/nix" = {
      kind = "runtime";
      group = "10-nix-runtime";
      paths = [ pkgs.nix ];
      stability = "stable";
      sharing = "global";
      priority = 92;
      securityClass = "trusted";
    };

    graph.nodes."language/nix" = {
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

    vscode.extensions = [
      "jnoortheen.nix-ide"
      "tamasfe.even-better-toml"
    ];

    vscode.settings = {
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

    tests.smoke = [
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
        name = "devpkg-doctor";
        command = [
          "devpkg"
          "doctor"
        ];
      }
    ];
  };
}
