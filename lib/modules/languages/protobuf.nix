{ pkgs, ... }:
{
  config.devcontainer.profiles."language/protobuf" = {
    kind = "language";
    group = "07-editor-support-tools";
    packages = with pkgs; [
      protobuf
      protols
    ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "protoc"
      "protols"
    ];

    vscode = {
      extensions."ianandhum.protobuf-support" = {
        native = false;
        bucket = "80-vscode-extensions-base";
        companionTools = [ "protols" ];
      };
      settings."protobuf-support.protols.path" = "/usr/bin/protols";
    };
  };
}
