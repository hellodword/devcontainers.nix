{
  pkgs,
  ...
}:
let
  packages = with pkgs; [
    just
    shellcheck
    shfmt
    editorconfig-core-c
  ];
in
{
  config.devcontainer.profiles."toolset/workflow-format" = {
    kind = "toolset";
    group = "07-workflow-format-tools";
    packages = packages;
    priority = 82;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "just"
      "shellcheck"
      "shfmt"
      "editorconfig"
    ];
  };
}
