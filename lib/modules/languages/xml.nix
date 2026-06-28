{ pkgs, ... }:
{
  config.devcontainer.profiles."language/xml" = {
    kind = "language";
    group = "editor-support-tools";
    packages = [ pkgs.lemminx ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "lemminx" ];

    vscode = {
      extensions."redhat.vscode-xml" = {
        native = false;
        bucket = "vscode-extensions-base";
        companionTools = [ "lemminx" ];
      };
      settings = {
        "xml.format.enabled" = true;
        "xml.server.preferBinary" = true;
        # The server binary /usr/bin/lemminx is not trusted. Running the file poses a threat to your system's security. Do you want to add this binary to the list of trusted binaries and run it?
        # "xml.server.binary.path" = "/usr/bin/lemminx";
      };
    };
  };
}
