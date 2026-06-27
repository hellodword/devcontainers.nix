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
      tests.capabilities = [ "nix.runtime" ];
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
          "nix.serverPath" = "/usr/bin/nixd";
          "nix.serverSettings" = {
            "nixd" = {
              "formatting" = {
                "command" = [ "/usr/bin/nixfmt" ];
              };
            };
          };
          "nix.formatterPath" = "/usr/bin/nixfmt";
        };
      };
      tests.capabilities = [ "language.nix" ];
    };
  };
}
