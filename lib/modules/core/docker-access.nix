{ lib, pkgs, config, ... }:
let
  cfg = config.devcontainer.dockerAccess;
  packages = with pkgs; [
    docker
    docker-buildx
    docker-compose
    docker-credential-helpers
  ];
  hostSocketEnv = {
    DOCKER_HOST = "unix:///var/run/docker.sock";
    DOCKER_BUILDKIT = "1";
    COMPOSE_DOCKER_CLI_BUILD = "1";
    BUILDKIT_PROGRESS = "plain";
  };
  remoteTcpEnv =
    {
      DOCKER_HOST = "tcp://${cfg.modes.remoteTcp.host}";
      DOCKER_BUILDKIT = "1";
      COMPOSE_DOCKER_CLI_BUILD = "1";
      BUILDKIT_PROGRESS = "plain";
    }
    // lib.optionalAttrs cfg.modes.remoteTcp.tls {
      DOCKER_TLS_VERIFY = "1";
      DOCKER_CERT_PATH = "/run/docker-certs";
    };
  resolvedMounts =
    if cfg.defaultMode == "remote-tcp" then
      lib.optional cfg.modes.remoteTcp.tls cfg.modes.remoteTcp.certMount
    else
      [ cfg.modes.hostSocket.mount ];
  resolvedEnv =
    if cfg.defaultMode == "remote-tcp" then
      remoteTcpEnv
    else
      hostSocketEnv;
in
{
  config = lib.mkIf cfg.enable {
    devcontainer.dockerAccess = {
      packages = packages;
      mounts = resolvedMounts;
      containerEnv = resolvedEnv;
    };

    devcontainer.packages = packages;

    devcontainer.graph.nodes."runtime/docker-access" = {
      kind = "runtime";
      group = "70-docker-access";
      paths = packages;
      stability = "medium";
      sharing = "single-image";
      priority = 60;
      securityClass = "docker-daemon-access";
    };

    devcontainer.lifecycle.tasks."docker-context-init" = {
      phase = "postCreate";
      once = true;
      user = "vscode";
      command = [ "devcontainer-docker-access" "init" ];
      timeoutSeconds = 30;
    };

    devcontainer.tests.smoke = [
      {
        name = "docker-version";
        command = [ "docker" "version" ];
      }
      {
        name = "docker-info";
        command = [ "docker" "info" ];
      }
      {
        name = "docker-buildx";
        command = [ "docker" "buildx" "version" ];
      }
      {
        name = "docker-compose";
        command = [ "docker" "compose" "version" ];
      }
      {
        name = "docker-build-run";
        command = [
          "bash"
          "-lc"
          ''
            cat >/tmp/Dockerfile <<'EOF'
            FROM busybox
            RUN echo ok >/ok
            CMD ["cat", "/ok"]
            EOF
            docker build -t docker-access-smoke /tmp
            docker run --rm docker-access-smoke
          ''
        ];
      }
    ];
  };
}
