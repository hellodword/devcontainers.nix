{ lib, config }:
let
  mkCase =
    {
      id,
      tags,
      command,
      requires ? [ ],
      timeoutSeconds ? 30,
    }:
    {
      inherit
        id
        tags
        command
        requires
        timeoutSeconds
        ;
    };
  baseline = [ "smoke" "baseline" "e2e-baseline" ];
  shellLocaleCommand = lib.concatStringsSep " && " [
    ''test "$LANG" = ${lib.escapeShellArg config.i18n.defaultLocale}''
    ''test "$LANGUAGE" = ${lib.escapeShellArg config.i18n.language}''
    ''test -r "$LOCALE_ARCHIVE"''
    ''test -e /etc/localtime''
    ''test -d /etc/zoneinfo''
    ''test "$TZDIR" = /etc/zoneinfo''
  ];
  shellInteractiveChecks =
    [
      "alias ll >/dev/null"
      "alias sha3-256sum >/dev/null"
    ]
    ++ lib.optionals config.programs.bash.completion.enable [
      "test -r /usr/share/bash-completion/bash_completion"
      "complete -p -D >/dev/null"
    ]
    ++ lib.optionals config.programs.bash.commandNotFound.enable [
      "type command_not_found_handle >/dev/null"
    ];
  devpkgCoreChecks =
    [ "devpkg list >/dev/null" ]
    ++ lib.optionals (config.programs.bash.enable && config.programs.bash.completion.enable) [
      "complete -p devpkg >/dev/null"
      "COMP_WORDS=(devpkg ad)"
      "COMP_CWORD=1"
      "_devpkg"
      ''printf '%s\n' "''${COMPREPLY[@]}" | grep -Fx add >/dev/null''
    ];
in
{
  "base.user" = mkCase {
    id = "base.user";
    tags = baseline ++ [ "base" "user" ];
    command = [
      "bash"
      "-lc"
      "test \"$(id -un)\" = vscode && test \"$(id -u)\" = 1000 && test \"$(id -gn)\" = vscode && test \"$(id -g)\" = 1000 && test \"$HOME\" = /home/vscode"
    ];
  };
  "base.filesystem" = mkCase {
    id = "base.filesystem";
    tags = baseline ++ [ "base" "filesystem" ];
    command = [
      "bash"
      "-lc"
      "test -w /tmp && test -w /var/tmp && test -w /workspaces && test \"$XDG_RUNTIME_DIR\" = /run/user/1000 && test -d \"$XDG_RUNTIME_DIR\""
    ];
  };
  "base.nix-store" = mkCase {
    id = "base.nix-store";
    tags = baseline ++ [ "base" "nix" ];
    command = [
      "bash"
      "-lc"
      "test -d /nix/var/nix && test -w /nix/store && test -w /nix/var/nix/db"
    ];
  };
  "fhs.runtime" = mkCase {
    id = "fhs.runtime";
    tags = baseline ++ [ "fhs" ];
    command = [
      "bash"
      "-lc"
      "test -x /bin/bash && test -x /bin/sh && test -x /usr/bin/env && test -e /etc/os-release && tar --version && (curl --version || wget --version)"
    ];
  };
  "fhs.ca-certificates" = mkCase {
    id = "fhs.ca-certificates";
    tags = baseline ++ [ "fhs" "ca-certificates" ];
    command = [
      "bash"
      "-lc"
      ''
        test -r "''${SSL_CERT_FILE:-}"
        test "''${NIX_SSL_CERT_FILE:-}" = "$SSL_CERT_FILE"
        curl --fail --silent --show-error --max-time 20 https://google.com >/dev/null
      ''
    ];
    timeoutSeconds = 45;
  };
  "fhs.nix-ld" = mkCase {
    id = "fhs.nix-ld";
    tags = baseline ++ [ "fhs" "nix-ld" ];
    command = [
      "bash"
      "-lc"
      ''
        test -x /lib64/ld-linux-x86-64.so.2
        test -n "''${NIX_LD:-}"
        test -n "''${NIX_LD_LIBRARY_PATH:-}"
        env -i NIX_LD="$NIX_LD" NIX_LD_LIBRARY_PATH="$NIX_LD_LIBRARY_PATH" PATH=/usr/bin \
          /lib64/ld-linux-x86-64.so.2 /usr/bin/env true
      ''
    ];
  };
  "nix.runtime" = mkCase {
    id = "nix.runtime";
    tags = baseline ++ [ "nix" "runtime" ];
    command = [
      "bash"
      "-lc"
      "nix --version && test -r /etc/nix/nix.conf && grep -F 'experimental-features = nix-command flakes' /etc/nix/nix.conf >/dev/null && test -f /usr/share/devcontainer/vscode/extensions-index.json && devcontainer-task-runner list >/dev/null"
    ];
  };
  "devpkg.core" = mkCase {
    id = "devpkg.core";
    tags = baseline ++ [ "devpkg" ];
    command = [
      "bash"
      (if config.programs.bash.enable && config.programs.bash.completion.enable then "-ic" else "-lc")
      (lib.concatStringsSep " && " devpkgCoreChecks)
    ];
  };
  "nixpkgs.config" = mkCase {
    id = "nixpkgs.config";
    tags = baseline ++ [ "nix" "config" ];
    command = [
      "bash"
      "-lc"
      "test \"$NIXPKGS_CONFIG\" = /etc/nixpkgs/config.nix && test -r \"$NIXPKGS_CONFIG\" && test \"$NIXPKGS_ALLOW_UNFREE\" = 1 && test \"$NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM\" = 1 && test \"$NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE\" = 1 && test \"$DO_NOT_TRACK\" = true && test \"$NIX_PAGER\" = cat && test \"$NIX_PATH\" = nixpkgs=/usr/share/devcontainer/nixpkgs && case \"$DEVPKG_NIXPKGS_REF\" in path:/nix/store/*-source) true ;; *) false ;; esac"
    ];
  };
  "shell.locale" = mkCase {
    id = "shell.locale";
    tags = baseline ++ [ "shell" "locale" ];
    command = [
      "bash"
      "-lc"
      shellLocaleCommand
    ];
  };
  "shell.interactive" = mkCase {
    id = "shell.interactive";
    tags = baseline ++ [ "shell" ];
    command = [
      "bash"
      "-ic"
      (lib.concatStringsSep " && " shellInteractiveChecks)
    ];
  };
  "fontconfig.core" = mkCase {
    id = "fontconfig.core";
    tags = baseline ++ [ "fontconfig" ];
    command = [
      "bash"
      "-lc"
      "command -v fc-cache >/dev/null && command -v fc-list >/dev/null && command -v fc-match >/dev/null && command -v fc-query >/dev/null && command -v fc-scan >/dev/null && command -v fc-validate >/dev/null && command -v fc-cat >/dev/null && command -v fc-conflist >/dev/null && command -v fc-pattern >/dev/null"
    ];
  };
  "fontconfig.cjk-emoji" = mkCase {
    id = "fontconfig.cjk-emoji";
    tags = baseline ++ [ "fontconfig" "cjk" "emoji" ];
    command = [
      "bash"
      "-lc"
      "fc-match 'sans-serif:lang=zh-cn:charset=0x95e8' | grep -F 'Noto Sans CJK SC' >/dev/null && fc-match 'serif:lang=zh-cn:charset=0x95e8' | grep -F 'Noto Serif CJK SC' >/dev/null && fc-match 'monospace:lang=zh-cn:charset=0x95e8' | grep -F 'Noto Sans Mono CJK SC' >/dev/null && fc-match 'emoji:charset=0x1f600' | grep -F 'Noto Color Emoji' >/dev/null"
    ];
  };
  "source-control.git-ssh" = mkCase {
    id = "source-control.git-ssh";
    tags = baseline ++ [ "source-control" "git" "ssh" ];
    command = [
      "bash"
      "-ic"
      "test -r /etc/gitconfig && git config --system --list >/dev/null && complete -p git >/dev/null && test -r /etc/ssh/ssh_config && ssh -G example.com >/dev/null"
    ];
  };
  "editor-support.tools" = mkCase {
    id = "editor-support.tools";
    tags = [ "smoke" "tooling" "editor-support" ];
    command = [
      "bash"
      "-lc"
      "yaml-language-server --version && minijinja --version && protoc --version && protols --version"
    ];
  };
  "nix-index.tools" = mkCase {
    id = "nix-index.tools";
    tags = [ "smoke" "tooling" "nix-index" ];
    command = [
      "bash"
      "-lc"
      "command -v nix-index >/dev/null && command -v nix-locate >/dev/null"
    ];
  };
  "codex.cli" = mkCase {
    id = "codex.cli";
    tags = [ "smoke" "tooling" "codex" ];
    command = [
      "codex"
      "--version"
    ];
  };
  "language.nix" = mkCase {
    id = "language.nix";
    tags = [ "smoke" "language" "nix" ];
    command = [
      "bash"
      "-lc"
      "nixd --version && nixfmt --version && alejandra --version && statix --help >/dev/null && deadnix --version"
    ];
  };
  "language.python" = mkCase {
    id = "language.python";
    tags = [ "smoke" "language" "python" ];
    command = [
      "bash"
      "-lc"
      "python --version && uv --version && uvx --version && python -c 'import ssl, sqlite3, ctypes'"
    ];
  };
  "language.nodejs" = mkCase {
    id = "language.nodejs";
    tags = [ "smoke" "language" "nodejs" "node" ];
    command = [
      "bash"
      "-lc"
      "node --version && npm --version && npx --version && pnpm --version && yarn --version && corepack --version && node-gyp --version && python --version && cc --version"
    ];
  };
  "language.go" = mkCase {
    id = "language.go";
    tags = [ "smoke" "language" "go" ];
    command = [
      "bash"
      "-lc"
      "go version && test \"$GOTOOLCHAIN\" = local && gopls version && dlv version && golangci-lint version && (govulncheck -version || govulncheck --version) && command -v gotests gomodifytags impl protoc-gen-go >/dev/null"
    ];
  };
  "language.rust" = mkCase {
    id = "language.rust";
    tags = [ "smoke" "language" "rust" ];
    command = [
      "bash"
      "-lc"
      "rustc --version && cargo --version && rustfmt --version && cargo clippy --version && rust-analyzer --version && rustup --version"
    ];
  };
  "language.flutter" = mkCase {
    id = "language.flutter";
    tags = [ "smoke" "language" "flutter" ];
    command = [
      "bash"
      "-lc"
      "flutter --version && dart --version && java -version && gradle --version && protoc-gen-dart --version"
    ];
    timeoutSeconds = 60;
  };
  "runtime.android-sdk" = mkCase {
    id = "runtime.android-sdk";
    tags = [ "smoke" "runtime" "android" "flutter" ];
    command = [
      "bash"
      "-lc"
      "command -v adb fastboot >/dev/null"
    ];
  };
  "runtime.browser-gui-gpu" = mkCase {
    id = "runtime.browser-gui-gpu";
    tags = [ "smoke" "runtime" "browser" "gui" "gpu" "flutter" ];
    command = [
      "bash"
      "-lc"
      "command -v chromium glxinfo >/dev/null"
    ];
  };
  "language.flutter-rust-bridge" = mkCase {
    id = "language.flutter-rust-bridge";
    tags = [ "smoke" "language" "flutter" "rust-bridge" ];
    command = [
      "bash"
      "-lc"
      "flutter_rust_bridge_codegen --version && sqlx --version && sqlite3 --version && command -v sqlitebrowser >/dev/null"
    ];
  };
  "web.python" = mkCase {
    id = "web.python";
    tags = [ "smoke" "web" "python" ];
    command = [
      "bash"
      "-lc"
      "python --version && uv --version && node --version && npm --version && pnpm --version && ruff --version && eslint --version && prettier --version"
    ];
  };
  "web.go" = mkCase {
    id = "web.go";
    tags = [ "smoke" "web" "go" ];
    command = [
      "bash"
      "-lc"
      "go version && gopls version && node --version && npm --version && pnpm --version"
    ];
  };
  "web.rust" = mkCase {
    id = "web.rust";
    tags = [ "smoke" "web" "rust" ];
    command = [
      "bash"
      "-lc"
      "rustc --version && cargo --version && node --version && npm --version && pnpm --version"
    ];
  };
}
