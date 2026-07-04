{ pkgs, ... }:
let
  languagePackages = with pkgs; [
    nixd
    nil
    man
    nixfmt
    alejandra
    statix
    deadnix
    treefmt
  ];
in
{
  config.devcontainer = {
    layers.bucketDefinitions = {
      "nix-runtime" = {
        order = 10900;
        owner = "languages/nix";
        purpose = "Nix CLI runtime.";
      };
      "nix-language" = {
        order = 11000;
        owner = "languages/nix";
        purpose = "Nix language servers, formatters, and linters.";
      };
      "vscode-extensions-nix" = {
        order = 61000;
        owner = "languages/nix";
        purpose = "Nix VS Code extension.";
      };
    };

    profiles = {
      "runtime/nix" = {
        kind = "runtime";
        group = "nix-runtime";
        packages = [ pkgs.nix ];
        priority = 92;
        stability = "stable";
        sharing = "global";
        securityClass = "trusted";
        provides.commands = [ "nix" ];
        tests.cases."nix.runtime" = {
          tags = [
            "smoke"
            "baseline"
            "nix"
            "runtime"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                nix --version
                nix config show >/dev/null
                test -r /etc/nix/nix.conf
                grep -F 'experimental-features = nix-command flakes' /etc/nix/nix.conf >/dev/null
                test -f /usr/share/devcontainer/vscode/extensions-index.json
                devcontainer-task-runner list >/dev/null
              '';
            }
          ];
        };
      };

      "language/nix" = {
        kind = "language";
        group = "nix-language";
        packages = languagePackages;
        priority = 90;
        stability = "stable";
        sharing = "global";
        securityClass = "trusted";
        provides.commands = [
          "nixd"
          "nil"
          "man"
          "nixfmt"
          "alejandra"
          "statix"
          "deadnix"
          "treefmt"
        ];
        vscode = {
          extensions."jnoortheen.nix-ide" = {
            native = false;
            bucket = "vscode-extensions-nix";
            companionTools = [
              "nixd"
              "nixfmt"
            ];
          };
          settings = {
            "nix.enableLanguageServer" = true;
            "nix.serverPath" = "/usr/bin/nixd";
            "nix.serverSettings" = {
              "nixd" = {
                "formatting" = {
                  "command" = [ "nixfmt" ];
                };
              };
            };
            "nix.formatterPath" = "nixfmt";
          };
        };
        tests.cases."language.nix" = {
          tags = [
            "smoke"
            "language"
            "nix"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                nixd --version
                nixfmt --version
                alejandra --version
                statix --help >/dev/null
                deadnix --version
              '';
            }
          ];
        };
      };
    };
  };
}
