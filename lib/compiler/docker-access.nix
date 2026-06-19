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
        remoteTcp = cfg.defaultMode == "remote-tcp";
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
  modes = {
    hostSocket = {
      enable = cfg.modes.hostSocket.enable;
      mount = cfg.modes.hostSocket.mount;
    };
    remoteTcp = {
      enable = cfg.modes.remoteTcp.enable;
      host = cfg.modes.remoteTcp.host;
      tls = cfg.modes.remoteTcp.tls;
      certMount = cfg.modes.remoteTcp.certMount;
    };
  };
  privilegeReport = privilegeReport;
}
