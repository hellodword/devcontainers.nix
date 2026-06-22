{
  pkgs,
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
  config.devcontainer.profiles."toolset/docker-client" = {
    kind = "toolset";
    group = "09-docker-client-tools";
    packages = packages;
    priority = 82;
    stability = "medium";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "docker"
      "docker-buildx"
      "docker-compose"
    ];
    env.variables = {
      DOCKER_BUILDKIT = "1";
      COMPOSE_DOCKER_CLI_BUILD = "1";
      BUILDKIT_PROGRESS = "plain";
    };
  };
}
