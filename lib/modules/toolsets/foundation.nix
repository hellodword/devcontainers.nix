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
  ];
in
{
  config.devcontainer.profiles."toolset/foundation" = {
    kind = "toolset";
    group = "02-foundation-tools";
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
