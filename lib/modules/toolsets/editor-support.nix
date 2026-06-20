{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    yaml-language-server
    minijinja
    protobuf
    protols
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.editorSupport.enable {
    environment.systemPackages = packages;
    devcontainer.graph.nodes."toolset/editor-support" = {
      kind = "toolset";
      group = "07-editor-support-tools";
      paths = packages;
      stability = "medium";
      sharing = "global";
      priority = 82;
      securityClass = "trusted";
    };
    devcontainer.tests.smoke = [
      {
        name = "editor-support-tools";
        command = [
          "bash"
          "-lc"
          "yaml-language-server --version && minijinja --version && protoc --version && protols --version"
        ];
      }
    ];
  };
}
