{ pkgs, ... }:
{
  config.devcontainer.profiles."runtime/base" = {
    kind = "runtime";
    group = "00-base-runtime";
    packages = [ pkgs.bashInteractive ];
    priority = 100;
    stability = "very-stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "bash" ];
  };
}
