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
      tests.cases."nix.runtime" = {
        tags = [
          "smoke"
          "baseline"
          "e2e-baseline"
          "nix"
          "runtime"
        ];
        command = [
          "bash"
          "-lc"
          "nix --version && test -r /etc/nix/nix.conf && grep -F 'experimental-features = nix-command flakes' /etc/nix/nix.conf >/dev/null && test -f /usr/share/devcontainer/vscode/extensions-index.json && devcontainer-task-runner list >/dev/null"
        ];
      };
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
        command = [
          "bash"
          "-lc"
          "nixd --version && nixfmt --version && alejandra --version && statix --help >/dev/null && deadnix --version"
        ];
      };
    };
  };
}
