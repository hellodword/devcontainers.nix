{ pkgs, ... }:
{
  config.devcontainer.profiles."language/toml" = {
    kind = "language";
    group = "editor-support-tools";
    packages = [ pkgs.taplo ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "taplo" ];

    vscode = {
      extensions."tamasfe.even-better-toml" = {
        native = false;
        bucket = "vscode-extensions-base";
        companionTools = [ "taplo" ];
      };
      settings = {
        "[toml]" = {
          "editor.defaultFormatter" = "tamasfe.even-better-toml";
        };
        "evenBetterToml.formatter.crlf" = false;
        "evenBetterToml.taplo.path" = "/usr/bin/taplo";
      };
    };
  };
}
