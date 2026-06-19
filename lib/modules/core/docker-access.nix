{ lib, pkgs, config, ... }:
let
  packages = with pkgs; [
    docker
    docker-buildx
    docker-compose
    docker-credential-helpers
  ];
  mounts = [
    "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock"
  ];
in
{
  config = lib.mkIf config.devcontainer.dockerAccess.enable {
    devcontainer.dockerAccess = {
      packages = packages;
      mounts = mounts;
      containerEnv = {
        DOCKER_HOST = "unix:///var/run/docker.sock";
        DOCKER_BUILDKIT = "1";
        COMPOSE_DOCKER_CLI_BUILD = "1";
        BUILDKIT_PROGRESS = "plain";
      };
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
        name = "docker-buildx";
        command = [ "docker" "buildx" "version" ];
      }
      {
        name = "docker-compose";
        command = [ "docker" "compose" "version" ];
      }
    ];
  };
}
