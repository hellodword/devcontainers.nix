{ pkgs, ... }:
{
  config.devcontainer.profiles."language/yaml" = {
    kind = "language";
    group = "07-editor-support-tools";
    packages = [ pkgs.yaml-language-server ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "yaml-language-server" ];

    vscode = {
      extensions."redhat.vscode-yaml" = {
        native = false;
        bucket = "80-vscode-extensions-base";
        companionTools = [ "yaml-language-server" ];
      };
      settings = {
        "[yaml]" = {
          "editor.defaultFormatter" = "redhat.vscode-yaml";
        };
        "redhat.telemetry.enabled" = false;
        "yaml.schemaStore.enable" = true;
        "yaml.format.enable" = true;
        "yaml.completion" = true;
      };
    };
  };
}
