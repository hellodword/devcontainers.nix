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
  config.devcontainer.profiles."toolset/fetch-archive" = {
    kind = "toolset";
    group = "04-fetch-archive-tools";
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
