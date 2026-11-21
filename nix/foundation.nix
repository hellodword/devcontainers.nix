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

  # gVisor's devpts returns EIO on blocking master reads while numReplicas == 0,
  # before a forked single-user Nix builder child opens /dev/pts/<N>. Retry EIO
  # until the first byte arrives (or a bounded startup window expires) and strip
  # LD_PRELOAD immediately in the constructor so child processes stay clean.
  wrappedNix =
    pkgs.runCommandCC "devcontainer-nix-${pkgs.nix.version}"
      {
        meta = removeAttrs pkgs.nix.meta [ "outputsToInstall" ];
      }
      ''
        mkdir -p "$out/bin" "$out/libexec/devcontainer"
        shim="$out/libexec/devcontainer/libgvisor_pty_shim.so"

        cat > shim.c <<'EOF'
        #define _GNU_SOURCE
        #include <dlfcn.h>
        #include <errno.h>
        #include <stdatomic.h>
        #include <stdint.h>
        #include <stdlib.h>
        #include <string.h>
        #include <time.h>
        #include <unistd.h>

        #define MAX_TRACKED_FDS 4096
        #define FIRST_READ_RETRY_NS 5000000000ULL

        static int (*real_posix_openpt)(int flags);
        static ssize_t (*real_read)(int fd, void *buf, size_t count);
        static int (*real_close)(int fd);
        static atomic_uint_least64_t first_byte_deadline_ns[MAX_TRACKED_FDS];

        static uint64_t monotonic_ns(void) {
          struct timespec ts;
          if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
            return 1;
          }
          return ((uint64_t)ts.tv_sec * 1000000000ULL) + (uint64_t)ts.tv_nsec;
        }

        static void strip_self_from_ld_preload(void) {
          const char *preload = getenv("LD_PRELOAD");
          if (preload == NULL || preload[0] == '\0') {
            return;
          }
          if (strcmp(preload, SHIM_SO_PATH) == 0) {
            unsetenv("LD_PRELOAD");
            return;
          }
          size_t len = strlen(preload);
          char *copy = malloc(len + 1);
          char *rebuilt = malloc(len + 1);
          if (copy == NULL || rebuilt == NULL) {
            free(copy);
            free(rebuilt);
            return;
          }
          memcpy(copy, preload, len + 1);
          rebuilt[0] = '\0';
          char *saveptr = NULL;
          for (char *tok = strtok_r(copy, ": ", &saveptr); tok != NULL;
               tok = strtok_r(NULL, ": ", &saveptr)) {
            if (strcmp(tok, SHIM_SO_PATH) == 0) {
              continue;
            }
            if (rebuilt[0] != '\0') {
              strcat(rebuilt, ":");
            }
            strcat(rebuilt, tok);
          }
          if (rebuilt[0] == '\0') {
            unsetenv("LD_PRELOAD");
          } else {
            setenv("LD_PRELOAD", rebuilt, 1);
          }
          free(copy);
          free(rebuilt);
        }

        __attribute__((constructor)) static void init_shim(void) {
          real_posix_openpt = dlsym(RTLD_NEXT, "posix_openpt");
          real_read = dlsym(RTLD_NEXT, "read");
          real_close = dlsym(RTLD_NEXT, "close");
          strip_self_from_ld_preload();
        }

        int posix_openpt(int flags) {
          if (real_posix_openpt == NULL) {
            real_posix_openpt = dlsym(RTLD_NEXT, "posix_openpt");
          }
          int fd = real_posix_openpt(flags);
          if (fd >= 0 && fd < MAX_TRACKED_FDS) {
            atomic_store_explicit(
                &first_byte_deadline_ns[fd],
                monotonic_ns() + FIRST_READ_RETRY_NS,
                memory_order_relaxed);
          }
          return fd;
        }

        int close(int fd) {
          if (real_close == NULL) {
            real_close = dlsym(RTLD_NEXT, "close");
          }
          if (fd >= 0 && fd < MAX_TRACKED_FDS) {
            atomic_store_explicit(&first_byte_deadline_ns[fd], 0, memory_order_relaxed);
          }
          return real_close(fd);
        }

        ssize_t read(int fd, void *buf, size_t count) {
          if (real_read == NULL) {
            real_read = dlsym(RTLD_NEXT, "read");
          }
          if (fd < 0 || fd >= MAX_TRACKED_FDS) {
            return real_read(fd, buf, count);
          }
          uint64_t deadline = atomic_load_explicit(
              &first_byte_deadline_ns[fd], memory_order_relaxed);
          if (deadline == 0) {
            return real_read(fd, buf, count);
          }
          for (;;) {
            ssize_t n = real_read(fd, buf, count);
            if (n > 0) {
              atomic_store_explicit(
                  &first_byte_deadline_ns[fd], 0, memory_order_relaxed);
              return n;
            }
            if (n == -1 && errno == EIO) {
              if (monotonic_ns() < deadline) {
                struct timespec req = {.tv_sec = 0, .tv_nsec = 1000000L};
                nanosleep(&req, NULL);
                continue;
              }
              atomic_store_explicit(
                  &first_byte_deadline_ns[fd], 0, memory_order_relaxed);
              errno = EIO;
              return -1;
            }
            return n;
          }
        }
        EOF

        cat > launcher.c <<'EOF'
        #define _GNU_SOURCE
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <unistd.h>

        int main(int argc, char **argv) {
          (void)argc;
          const char *existing = getenv("LD_PRELOAD");
          if (existing == NULL || existing[0] == '\0') {
            if (setenv("LD_PRELOAD", SHIM_SO_PATH, 1) != 0) {
              perror("setenv LD_PRELOAD");
              return 126;
            }
          } else {
            size_t needed = strlen(SHIM_SO_PATH) + 1 + strlen(existing) + 1;
            char *combined = malloc(needed);
            if (combined == NULL) {
              perror("malloc");
              return 126;
            }
            snprintf(combined, needed, "%s:%s", SHIM_SO_PATH, existing);
            if (setenv("LD_PRELOAD", combined, 1) != 0) {
              perror("setenv LD_PRELOAD");
              free(combined);
              return 126;
            }
            free(combined);
          }
          execv(REAL_NIX_BIN, argv);
          perror("execv nix");
          return 127;
        }
        EOF

        "$CC" -shared -fPIC -O2 -Wall -Wextra -Werror \
          -DSHIM_SO_PATH="\"$shim\"" \
          -o "$shim" shim.c -ldl

        "$CC" -O2 -Wall -Wextra -Werror \
          -DSHIM_SO_PATH="\"$shim\"" \
          -DREAL_NIX_BIN="\"${pkgs.nix}/bin/nix\"" \
          -o "$out/bin/nix" launcher.c

        for tool in ${pkgs.nix}/bin/*; do
          name="$(basename "$tool")"
          if [ "$name" != "nix" ]; then
            ln -s nix "$out/bin/$name"
          fi
        done

        for sub in etc lib; do
          if [ -e "${pkgs.nix}/$sub" ]; then
            ln -s "${pkgs.nix}/$sub" "$out/$sub"
          fi
        done
        mkdir -p "$out/share"
        for item in ${pkgs.nix}/share/*; do
          ln -s "$item" "$out/share/$(basename "$item")"
        done
        if [ -d "${pkgs.nix.man or ""}/share/man" ]; then
          ln -s "${pkgs.nix.man}/share/man" "$out/share/man"
        fi
        for item in ${pkgs.nix}/libexec/*; do
          ln -s "$item" "$out/libexec/$(basename "$item")"
        done

        mkdir -p "$TMPDIR/home" "$TMPDIR/nix-state" "$TMPDIR/nix-log" "$TMPDIR/nix-conf"
        HOME="$TMPDIR/home" \
          NIX_STATE_DIR="$TMPDIR/nix-state" \
          NIX_LOG_DIR="$TMPDIR/nix-log" \
          NIX_CONF_DIR="$TMPDIR/nix-conf" \
          "$out/bin/nix" --version >/dev/null
        HOME="$TMPDIR/home" \
          NIX_STATE_DIR="$TMPDIR/nix-state" \
          NIX_LOG_DIR="$TMPDIR/nix-log" \
          NIX_CONF_DIR="$TMPDIR/nix-conf" \
          "$out/bin/nix-store" --version >/dev/null
      '';

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
    DEVPKG_RUNTIME_LIBRARY_PROFILE = runtimeLibProfile;
    DEVPKG_BUILD_LIBRARY_PROFILE = buildLibProfile;
    NIX_LD_LIBRARY_PATH = "${pkgs.glibc}/lib:${pkgs.stdenv.cc.cc.lib}/lib:${runtimeLibProfile}/lib:${buildLibProfile}/lib";
    PKG_CONFIG_PATH = "${buildLibProfile}/lib/pkgconfig:${buildLibProfile}/share/pkgconfig";
    CMAKE_PREFIX_PATH = buildLibProfile;
    CPATH = "${buildLibProfile}/include";
    LIBRARY_PATH = "${buildLibProfile}/lib:${buildLibProfile}/lib64";

    NIXPKGS_CONFIG = "/etc/nixpkgs/config.nix";
    NIXPKGS_ALLOW_UNFREE = "1";
    NIX_PAGER = "cat";
    NIX_PATH = "nixpkgs=/usr/share/devcontainer/nixpkgs";
    DEVPKG_NIXPKGS_REF = "path:${inputs.nixpkgs.outPath}";
    DEVPKG_NIXPKGS_CACHE_KEY = nixpkgsCacheKey;
    DEVPKG_SYSTEM = "x86_64-linux";
    DOCKER_BUILDKIT = "1";
    COMPOSE_DOCKER_CLI_BUILD = "1";
    BUILDKIT_PROGRESS = "plain";
    DO_NOT_TRACK = "true";
    PAGER = "less";
    EDITOR = "vim";
    VISUAL = "vim";
  };

  agentPathSegments = [
    "/home/vscode/.local/share/devcontainer/bin"
    "/home/vscode/.local/share/nix-profile/bin"
    "/home/vscode/.nix-profile/bin"
    "/usr/local/bin"
    "/usr/bin"
  ];

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
    usrPackages
    storeDeps
    fontsRoot
    baseEnv
    agentPathSegments
    mkShellFiles
    fhsSymlinks
    nixDaemonConf
    buildLibProfile
    ;
}
