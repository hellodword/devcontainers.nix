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
  config.devcontainer.profiles = {
    "runtime/nix" = {
      kind = "runtime";
      group = "10-nix-runtime";
      packages = [ pkgs.nix ];
      priority = 92;
      stability = "stable";
      sharing = "global";
      securityClass = "trusted";
      provides.commands = [ "nix" ];
      tests.smoke = [
        {
          name = "nix-version";
          command = [
            "nix"
            "--version"
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
      ];
    };

    "language/nix" = {
      kind = "language";
      group = "11-nix-language";
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
          bucket = "81-vscode-extensions-nix";
          companionTools = [
            "nixd"
            "nixfmt"
          ];
        };
        settings = {
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
      };
      tests.smoke = [
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
      ];
    };
  };
}
