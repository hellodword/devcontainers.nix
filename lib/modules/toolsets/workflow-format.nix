{ ... }:
{
  config.devcontainer.layers.bucketDefinitions."workflow-format-tools" = {
    order = 10500;
    owner = "toolsets/workflow-format";
    purpose = "Workflow, formatter, shell linting, and editorconfig tools.";
  };

  config.devcontainer.profiles."toolset/workflow-format" = {
    kind = "toolset";
    group = "workflow-format-tools";
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
      "toolset/workflow-format/smoke"
    ];
  };

  config.devcontainer.profiles."toolset/workflow-format/smoke" = {
    kind = "toolset";
    group = "workflow-format-tools";
    packages = [ ];
    priority = 82;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    tests.cases."workflow-format.tools" = {
      tags = [
        "smoke"
        "tooling"
        "workflow-format"
      ];
      command = [
        "bash"
        "-lc"
        "just --version && just-lsp --version && shfmt --version"
      ];
    };
  };
}
