{
  pkgs,
  ...
}:
let
  packages = with pkgs; [
    curl
    wget
    aria2
    rsync
    unzip
    zip
    p7zip
    bzip2
  ];
in
{
  config.devcontainer.layers.bucketDefinitions."fetch-archive-tools" = {
    order = 10200;
    owner = "toolsets/fetch-archive";
    purpose = "Network fetch and archive extraction tools.";
  };

  config.devcontainer.profiles."toolset/fetch-archive" = {
    kind = "toolset";
    group = "fetch-archive-tools";
    packages = packages;
    priority = 88;
    stability = "stable";
    sharing = "global";
    securityClass = "networked";
    provides.commands = [
      "curl"
      "wget"
      "aria2c"
      "rsync"
      "unzip"
      "zip"
      "7z"
      "bzip2"
    ];
  };
}
