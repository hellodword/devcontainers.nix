{ lib }:
{ config }:
let
  cfg = config.devcontainer.dockerAccess;
  privilegeReport =
    if cfg.enable then
      {
        level = "high";
        reason = "docker-daemon-access";
        hostSocket = cfg.defaultMode == "host-socket";
        remoteTls = cfg.defaultMode == "remote-tcp-tls";
      }
    else
      {
        level = "none";
        reason = "disabled";
      };
in
{
  enabled = cfg.enable;
  packages = map toString cfg.packages;
  mounts = cfg.mounts;
  containerEnv = cfg.containerEnv;
  defaultMode = cfg.defaultMode;
  privilegeReport = privilegeReport;
}
