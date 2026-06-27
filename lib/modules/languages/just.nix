{ pkgs, ... }:
{
  config.devcontainer.profiles."language/just" = {
    kind = "language";
    group = "07-workflow-format-tools";
    packages = with pkgs; [
      just
      just-lsp
    ];
    priority = 82;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "just"
      "just-lsp"
    ];

    vscode = {
      extensions."nefrob.vscode-just-syntax" = {
        native = false;
        bucket = "80-vscode-extensions-base";
        companionTools = [
          "just"
          "just-lsp"
        ];
      };
      settings = {
        "vscode-just.justPath" = "/usr/bin/just";
        "vscode-just.lspPath" = "/usr/bin/just-lsp";
      };
    };
  };
}
