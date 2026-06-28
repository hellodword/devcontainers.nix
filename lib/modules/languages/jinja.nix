{ pkgs, ... }:
{
  config.devcontainer.profiles."language/jinja" = {
    kind = "language";
    group = "editor-support-tools";
    packages = [ pkgs.minijinja ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "minijinja-cli" ];

    vscode.extensions."samuelcolvin.jinjahtml" = {
      native = false;
      bucket = "vscode-extensions-base";
      companionTools = [ ];
      notes = "Syntax support only; no Jinja LSP is configured.";
    };
  };
}
