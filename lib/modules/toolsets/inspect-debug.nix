{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    procps
    psmisc
    lsof
    htop
    btop
    strace
    iproute2
    iputils
    dnsutils
    netcat
    socat
    openssl
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.inspectDebug.enable {
    devcontainer.packages = packages;
    devcontainer.graph.nodes."toolset/inspect-debug" = {
      kind = "toolset";
      group = "06-inspect-debug-tools";
      paths = packages;
      stability = "medium";
      sharing = "global";
      priority = 84;
      securityClass = "networked";
    };
  };
}
