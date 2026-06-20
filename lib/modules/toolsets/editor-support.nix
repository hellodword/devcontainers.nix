{
  pkgs,
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
  config.devcontainer.profiles."toolset/editor-support" = {
    kind = "toolset";
    group = "07-editor-support-tools";
    packages = packages;
    priority = 82;
    stability = "medium";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "yaml-language-server"
      "minijinja"
      "protoc"
      "protols"
    ];
    tests.smoke = [
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
