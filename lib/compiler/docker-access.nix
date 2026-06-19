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
  modes = {
    hostSocket = {
      enable = cfg.modes.hostSocket.enable;
      mount = cfg.modes.hostSocket.mount;
    };
    remoteTcpTls = {
      enable = cfg.modes.remoteTcpTls.enable;
      host = cfg.modes.remoteTcpTls.host;
      certMount = cfg.modes.remoteTcpTls.certMount;
    };
  };
  privilegeReport = privilegeReport;
}
