{
  pkgs,
  ...
}:
let
  packages = with pkgs; [
    postgresql
    redis
    httpie
  ];
in
{
  config.devcontainer.profiles."toolset/data-network" = {
    kind = "toolset";
    group = "08-data-network-tools";
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
