# Shared foundation packages, FHS loader symlinks, /etc configuration, shell startup, and base OCI Env.
{
  pkgs,
  lib,
  inputs,
  cache,
  runtime,
}:
let
  shellAndArchivePackages = with pkgs; [
    bashInteractive
    bash-completion
    glibcLocales
    coreutils
    findutils
    gnused
    gnugrep
    gawk
    diffutils
    gnutar
    gzip
    xz
    zstd
    bzip2
    unzip
    zip
    p7zip
    rsync
    file
    which
    less
    vim
    util-linux
    sqlite
    time
  ];

  vcsAndNetworkPackages = with pkgs; [
    git
    git-lfs
    openssh
    sshpass
    gnupg
    pinentry-curses
    delta
    curl
    wget
    aria2
    httpie
    ripgrep
    fd
    fzf
    tree
    bat
    eza
    jq
    yq-go
    procps
    psmisc
    lsof
    htop
    btop
    strace
    iproute2
    iputils
    dnsutils
    netcat
    socat
    openssl
    net-tools
  ];

  wrappedNix = import ./gvisor-pty-shim.nix { inherit pkgs; };

  containerAndNixPackages = with pkgs; [
    just
    docker-client
    docker-buildx
    docker-compose
    docker-credential-helpers
    wrappedNix
    nix-index-with-db
    comma-with-db
  ];

  fontPackages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];

  linuxRuntimePackages = [
    pkgs.glibc
    pkgs.stdenv.cc.cc.lib
    pkgs.nix-ld
    pkgs.dockerTools.caCertificates
    pkgs.cacert
    pkgs.tzdata
    pkgs.iana-etc
    pkgs.mailcap
    pkgs.getent
    pkgs.ncurses
    pkgs.shared-mime-info
    (lib.getBin pkgs.glib)
    pkgs.dbus
    pkgs.tini
    pkgs.fontconfig
  ]
  ++ fontPackages;

  usrPackages =
    shellAndArchivePackages
    ++ vcsAndNetworkPackages
    ++ containerAndNixPackages
    ++ [
      pkgs.getent
      pkgs.ncurses
      pkgs.shared-mime-info
      (lib.getBin pkgs.glib)
      pkgs.dbus
      pkgs.tini
      pkgs.fontconfig
    ]
    ++ fontPackages
    ++ runtime.baseHelpers;

  defaultFontsConf = pkgs.writeText "fc-52-devcontainer-default-fonts.conf" ''
    <?xml version='1.0'?>
    <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
    <fontconfig>
      <alias binding="same">
        <family>sans-serif</family>
        <prefer>
          <family>Noto Sans CJK SC</family>
          <family>Noto Sans</family>
        </prefer>
      </alias>
      <alias binding="same">
        <family>serif</family>
        <prefer>
          <family>Noto Serif CJK SC</family>
          <family>Noto Serif</family>
        </prefer>
      </alias>
      <alias binding="same">
        <family>monospace</family>
        <prefer>
          <family>Noto Sans Mono CJK SC</family>
          <family>Noto Sans Mono</family>
        </prefer>
      </alias>
      <alias binding="same">
        <family>emoji</family>
        <prefer>
          <family>Noto Color Emoji</family>
        </prefer>
      </alias>
    </fontconfig>
  '';

  fontsConf = pkgs.makeFontsConf {
    fontconfig = pkgs.fontconfig;
    fontDirectories = fontPackages;
    includes = [ "/etc/fonts/conf.d" ];
  };

  fontconfigOut = lib.getOutput "out" pkgs.fontconfig;

  fontsRoot = pkgs.runCommand "devcontainer-fonts-etc" { } ''
    mkdir -p "$out/etc/fonts/conf.d"
    ln -s ${fontsConf} "$out/etc/fonts/fonts.conf"
    for conf in ${fontconfigOut}/etc/fonts/conf.d/*; do
      ln -s "$conf" "$out/etc/fonts/conf.d/$(basename "$conf")"
    done
    ln -s ${defaultFontsConf} "$out/etc/fonts/conf.d/52-devcontainer-default-fonts.conf"
  '';

  storeDeps = lib.unique (
    usrPackages
    ++ linuxRuntimePackages
    ++ [
      fontsConf
      defaultFontsConf
    ]
  );

  nixpkgsCacheKey =
    if inputs.nixpkgs ? rev then
      inputs.nixpkgs.rev
    else if inputs.nixpkgs ? narHash then
      inputs.nixpkgs.narHash
    else
      toString inputs.nixpkgs.outPath;

  runtimeLibProfile = "/home/vscode/.local/share/devpkg/runtime-libraries/profile";
  buildLibProfile = "/home/vscode/.local/share/devpkg/build-libraries/profile";

  baseEnv = {
    USER = "vscode";
    LOGNAME = "vscode";
    HOME = "/home/vscode";
    SHELL = "/bin/bash";
    XDG_CONFIG_HOME = "/home/vscode/.config";
    XDG_CACHE_HOME = "/home/vscode/.cache";
    XDG_DATA_HOME = "/home/vscode/.local/share";
    XDG_STATE_HOME = "/home/vscode/.local/state";
    XDG_RUNTIME_DIR = "/run/user/1000";
    XDG_CONFIG_DIRS = "/etc/xdg";
    XDG_DATA_DIRS = "/usr/local/share:/usr/share";

    LANG = "en_US.UTF-8";
    LANGUAGE = "en_US:en";
    LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
    TZDIR = "/etc/zoneinfo";
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    CURL_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
    GIT_SSL_CAINFO = "/etc/ssl/certs/ca-certificates.crt";

    NIX_LD = "${pkgs.glibc}/lib/ld-linux-x86-64.so.2";
    NIX_LD_LIBRARY_PATH = "${pkgs.glibc}/lib:${pkgs.stdenv.cc.cc.lib}/lib:${runtimeLibProfile}/lib:${buildLibProfile}/lib";
    PKG_CONFIG_PATH = "${buildLibProfile}/lib/pkgconfig:${buildLibProfile}/share/pkgconfig";
    CMAKE_PREFIX_PATH = buildLibProfile;
    CPATH = "${buildLibProfile}/include";
    LIBRARY_PATH = "${buildLibProfile}/lib:${buildLibProfile}/lib64";

    NIXPKGS_CONFIG = "/etc/nixpkgs/config.nix";
    NIXPKGS_ALLOW_UNFREE = "1";
    NIX_PAGER = "cat";
    NIX_PATH = "nixpkgs=/usr/share/devcontainer/nixpkgs";
    DOCKER_BUILDKIT = "1";
    COMPOSE_DOCKER_CLI_BUILD = "1";
    BUILDKIT_PROGRESS = "plain";
    DO_NOT_TRACK = "true";
    PAGER = "less";
    EDITOR = "vim";
    VISUAL = "vim";
  };

  mkShellFiles =
    {
      envAttrs,
      pathSegments,
    }:
    let
      sortedKeys = lib.sort lib.lessThan (builtins.filter (k: k != "PATH") (builtins.attrNames envAttrs));
      exportBlock = lib.concatMapStringsSep "\n" (key: ''
        if [ -z "''${${key}+x}" ]; then
          export ${key}=${lib.escapeShellArg envAttrs.${key}}
        fi
      '') sortedKeys;
      pathBlock = ''
        __devcontainer_append_path() {
          [ -n "$1" ] || return 0
          case ":$__devcontainer_path:" in
            *:"$1":*) ;;
            *)
              if [ -n "$__devcontainer_path" ]; then
                __devcontainer_path="$__devcontainer_path:$1"
              else
                __devcontainer_path="$1"
              fi
              ;;
          esac
        }
        __devcontainer_path=""
        __devcontainer_ifs="$IFS"
        IFS=:
        for __seg in ''${PATH:-}; do
          __devcontainer_append_path "$__seg"
        done
        IFS="$__devcontainer_ifs"
        ${lib.concatMapStringsSep "\n" (
          seg: "__devcontainer_append_path ${lib.escapeShellArg seg}"
        ) pathSegments}
        export PATH="$__devcontainer_path"
        unset -f __devcontainer_append_path 2>/dev/null || true
        unset __devcontainer_path __devcontainer_ifs __seg
      '';
      guiSourceBlock = ''
        __gui_env="''${DEVCONTAINER_GUI_ENV_FILE:-''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/devcontainer-gui-env.sh}"
        if [ -r "$__gui_env" ]; then
          . "$__gui_env"
        fi
        unset __gui_env
      '';
      interactiveBlock = ''
        alias l='ls -CF'
        alias la='ls -A'
        alias ll='ls -alF'
        alias ls='ls --color=auto'
        alias grep='grep --color=auto'
        alias sha3-224sum='openssl dgst -sha3-224'
        alias sha3-256sum='openssl dgst -sha3-256'
        alias sha3-384sum='openssl dgst -sha3-384'
        alias sha3-512sum='openssl dgst -sha3-512'

        PROMPT_DIRTRIM=3
        if [ -t 1 ]; then
          PS1='\[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '
        else
          PS1='\u@\h:\w\$ '
        fi

        HISTFILE="''${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
        HISTSIZE=50000
        HISTFILESIZE=100000
        HISTCONTROL=ignoreboth:erasedups
        shopt -s histappend
        shopt -s checkwinsize

        if ! declare -F _init_completion >/dev/null 2>&1 && [ -r /usr/share/bash-completion/bash_completion ]; then
          . /usr/share/bash-completion/bash_completion
        fi
        if ! complete -p devpkg >/dev/null 2>&1 && [ -r /usr/share/bash-completion/completions/devpkg ]; then
          . /usr/share/bash-completion/completions/devpkg
        fi
        if ! complete -p git >/dev/null 2>&1 && [ -r ${pkgs.git}/share/bash-completion/completions/git ]; then
          . ${pkgs.git}/share/bash-completion/completions/git
        fi

        command_not_found_handle() {
          local cmd="$1"
          shift || true
          printf '%s: command not found\n' "$cmd" >&2
          if command -v nix-locate >/dev/null 2>&1; then
            {
              nix-locate --minimal --whole-name --at-root "/usr/bin/$cmd" 2>/dev/null || true
              nix-locate --minimal --whole-name --at-root "/bin/$cmd" 2>/dev/null || true
            } | sort -u | head -n 20 >&2 || true
          fi
          return 127
        }
      '';
      profileText = ''
        # System profile for devcontainers.nix images.
        ${exportBlock}
        ${pathBlock}
        ${guiSourceBlock}

        if [ -d /etc/profile.d ]; then
          for script in /etc/profile.d/*.sh; do
            [ -e "$script" ] || continue
            [ -r "$script" ] && . "$script"
          done
          unset script
        fi

        case "$-" in
          *i*)
            if [ -n "''${BASH_VERSION:-}" ] && [ -r /etc/bashrc ]; then
              . /etc/bashrc
            fi
            ;;
        esac
      '';
      bashrcText = ''
        # System bashrc for devcontainers.nix images.
        if [ -z "''${BASH_VERSION:-}" ]; then
          return 0 2>/dev/null || exit 0
        fi
        case "$-" in
          *i*) ;;
          *) return 0 2>/dev/null || exit 0 ;;
        esac
        ${exportBlock}
        ${pathBlock}
        ${guiSourceBlock}
        ${interactiveBlock}
      '';
    in
    {
      inherit profileText bashrcText;
      bashBashrcText = bashrcText;
    };

  fhsSymlinks = [
    {
      target = "/usr/lib64/ld-linux-x86-64.so.2";
      source = "${pkgs.nix-ld}/libexec/nix-ld";
    }
    {
      target = "/usr/lib/libc.so.6";
      source = "${pkgs.glibc}/lib/libc.so.6";
    }
    {
      target = "/usr/lib/libstdc++.so.6";
      source = "${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6";
    }
  ];

  nixDaemonConf = cache.public.daemonConf;
in
{
  inherit
    wrappedNix
    usrPackages
    storeDeps
    fontsRoot
    baseEnv
    mkShellFiles
    fhsSymlinks
    nixDaemonConf
    nixpkgsCacheKey
    runtimeLibProfile
    buildLibProfile
    ;
}
