{ ... }:
{
  config.devcontainer.profiles."toolset/workflow-format" = {
    kind = "toolset";
    group = "07-workflow-format-tools";
    packages = [ ];
    priority = 82;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    composition.role = "bundle";
    includes = [
      "language/just"
      "editor/shellcheck"
      "tool/shell-format"
      "tool/editorconfig"
    ];
    tests.capabilities = [ "workflow-format.tools" ];
  };
}
