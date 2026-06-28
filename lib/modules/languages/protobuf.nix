{ pkgs, ... }:
{
  config.devcontainer.profiles."language/protobuf" = {
    kind = "language";
    group = "editor-support-tools";
    packages = with pkgs; [
      protobuf
      protols
      buf
      protolint
      grpcurl
      api-linter
    ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "protoc"
      "protols"
      "buf"
      "protolint"
      "grpcurl"
      "api-linter"
    ];

    vscode = {
      extensions."drblury.protobuf-vsc" = {
        native = false;
        bucket = "vscode-extensions-base";
        companionTools = [
          "protoc"
          "buf"
          "protolint"
          "grpcurl"
          "api-linter"
        ];
      };
      settings = {
        "[proto]" = {
          "editor.defaultFormatter" = "DrBlury.protobuf-vsc";
        };
        "[textproto]" = {
          "editor.defaultFormatter" = "DrBlury.protobuf-vsc";
        };
        "protobuf.formatter.enabled" = true;
        "protobuf.formatter.preset" = "minimal";
        "protobuf.protoc.path" = "/usr/bin/protoc";
        "protobuf.grpcurl.path" = "/usr/bin/grpcurl";
        "protobuf.externalLinter.protolintPath" = "/usr/bin/protolint";
        "protobuf.externalLinter.apiLinterPath" = "/usr/bin/api-linter";
        "protobuf.externalLinter.linter" = "buf";
        "protobuf.externalLinter.enabled" = true;
        "protobuf.externalLinter.bufPath" = "/usr/bin/buf";
        "protobuf.buf.useManaged" = false;
        "protobuf.buf.path" = "/usr/bin/buf";
        "protobuf.autoDetection.enabled" = false;
      };
    };
  };
}
