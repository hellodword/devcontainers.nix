{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    docker
    docker-buildx
    docker-compose
    docker-credential-helpers
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.dockerClient.enable {
    devcontainer.packages = packages;

    devcontainer.env.container = {
      DOCKER_BUILDKIT = "1";
      COMPOSE_DOCKER_CLI_BUILD = "1";
      BUILDKIT_PROGRESS = "plain";
    };
    devcontainer.env.origins.container = {
      DOCKER_BUILDKIT = [ "toolsets.docker-client" ];
      COMPOSE_DOCKER_CLI_BUILD = [ "toolsets.docker-client" ];
      BUILDKIT_PROGRESS = [ "toolsets.docker-client" ];
    };

    devcontainer.graph.nodes."toolset/docker-client" = {
      kind = "toolset";
      group = "09-docker-client-tools";
      paths = packages;
      stability = "medium";
      sharing = "global";
      priority = 82;
      securityClass = "trusted";
    };

    devcontainer.tests.smoke = [
      {
        name = "docker-client";
        command = [
          "docker"
          "--version"
        ];
      }
      {
        name = "docker-buildx";
        command = [
          "docker"
          "buildx"
          "version"
        ];
      }
      {
        name = "docker-compose";
        command = [
          "docker"
          "compose"
          "version"
        ];
      }
      {
        name = "docker-remote-version";
        command = [
          "docker"
          "version"
        ];
      }
    ];
  };
}
