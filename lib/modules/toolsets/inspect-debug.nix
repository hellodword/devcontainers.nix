{
  pkgs,
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
    net-tools
  ];
in
{
  config.devcontainer.layers.bucketDefinitions."06-inspect-debug-tools" = {
    order = 7;
    owner = "toolsets/inspect-debug";
    purpose = "Process, network, and debugging inspection tools.";
  };

  config.devcontainer.profiles."toolset/inspect-debug" = {
    kind = "toolset";
    group = "06-inspect-debug-tools";
    packages = packages;
    priority = 84;
    stability = "medium";
    sharing = "global";
    securityClass = "networked";
    provides.commands = [
      "ps"
      "killall"
      "lsof"
      "htop"
      "btop"
      "strace"
      "ip"
      "ping"
      "dig"
      "nc"
      "socat"
      "openssl"
    ];
  };
}
