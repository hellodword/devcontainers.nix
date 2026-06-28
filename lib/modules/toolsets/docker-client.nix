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
  config.devcontainer.layers.bucketDefinitions."docker-client-tools" = {
    order = 10800;
    owner = "toolsets/docker-client";
    purpose = "Docker CLI, Buildx, Compose, and credential helpers.";
  };

  config.devcontainer.profiles."toolset/docker-client" = {
    kind = "toolset";
    group = "docker-client-tools";
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
