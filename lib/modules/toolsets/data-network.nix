{
  pkgs,
  ...
}:
let
  packages = with pkgs; [
    httpie
  ];
in
{
  config.devcontainer.layers.bucketDefinitions."data-network-tools" = {
    order = 10700;
    owner = "toolsets/data-network";
    purpose = "Database and HTTP client tools.";
  };

  config.devcontainer.profiles."toolset/data-network" = {
    kind = "toolset";
    group = "data-network-tools";
    packages = packages;
    priority = 70;
    stability = "medium";
    sharing = "image-family";
    securityClass = "networked";
    provides.commands = [
      "psql"
      "redis-cli"
      "http"
    ];
  };
}
