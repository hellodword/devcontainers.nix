{ ... }:
{
  config.devcontainer.profiles."editor/base" = {
    kind = "editor";
    group = "80-vscode-extensions-base";
    packages = [ ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    composition.role = "bundle";
    includes = [
      "editor/core"
      "editor/prettier"
      "language/yaml"
      "editor/markdown-preview"
      "language/xml"
      "language/toml"
      "language/jinja"
      "language/protobuf"
      "editor/shellcheck"
    ];
  };
}
