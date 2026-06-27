{ pkgs, ... }:
{
  config.devcontainer.profiles."language/xml" = {
    kind = "language";
    group = "07-editor-support-tools";
    packages = [ pkgs.lemminx ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "lemminx" ];

    vscode = {
      extensions."redhat.vscode-xml" = {
        native = false;
        bucket = "80-vscode-extensions-base";
        companionTools = [ "lemminx" ];
      };
      settings = {
        "xml.format.enabled" = true;
        "xml.server.preferBinary" = true;
        "xml.server.binary.path" = "/usr/bin/lemminx";
      };
    };
  };
}
