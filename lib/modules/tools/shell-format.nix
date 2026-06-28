{ pkgs, ... }:
{
  config.devcontainer.profiles."tool/shell-format" = {
    kind = "tool";
    group = "workflow-format-tools";
    packages = [ pkgs.shfmt ];
    priority = 82;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "shfmt" ];
  };
}
