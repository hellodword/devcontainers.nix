{ pkgs, ... }:
{
  config.devcontainer.layers.bucketDefinitions."00-base-runtime" = {
    order = 0;
    owner = "runtimes/base";
    purpose = "Minimal baseline runtime shell used by all images.";
  };

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
