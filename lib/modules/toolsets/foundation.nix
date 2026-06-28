{
  pkgs,
  ...
}:
let
  packages = with pkgs; [
    bashInteractive
    coreutils
    findutils
    gnused
    gnugrep
    gawk
    gnutar
    gzip
    xz
    zstd
    file
    which
    less
    vim
    util-linux
    sqlite
    diffutils
  ];
in
{
  config.devcontainer.layers.bucketDefinitions."foundation-tools" = {
    order = 10000;
    owner = "toolsets/foundation";
    purpose = "Foundational command-line tools available in all practical images.";
  };

  config.devcontainer.profiles."toolset/foundation" = {
    kind = "toolset";
    group = "foundation-tools";
    packages = packages;
    priority = 95;
    stability = "very-stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [
      "bash"
      "coreutils"
      "find"
      "sed"
      "grep"
      "awk"
      "tar"
      "gzip"
      "xz"
      "zstd"
      "file"
      "which"
      "less"
      "vim"
      "sqlite3"
    ];
  };
}
