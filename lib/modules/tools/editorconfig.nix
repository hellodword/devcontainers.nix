{ pkgs, ... }:
{
  config.devcontainer.profiles."tool/editorconfig" = {
    kind = "tool";
    group = "07-workflow-format-tools";
    packages = [ pkgs.editorconfig-core-c ];
    priority = 82;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "editorconfig" ];
  };
}
