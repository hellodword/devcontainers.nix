{ pkgs, lib }:
{
  config,
  compiledFilesystem,
}:
let
  user = config.devcontainer.user;
  cfg = config.devcontainer.browserSandbox;
  browserOrder = [
    "chromium"
    "google-chrome"
    "microsoft-edge"
  ];
  # Keep these paths and shim behavior in sync with docs/browser-sandbox.md and runtime/devpkg/main.sh.
  wrapperHelperRoot = "/run/wrappers/bin";
  stableHelperRoot = "/opt/devcontainer/browser-sandbox";
  chromiumSandboxExecutableName =
    pkgs.chromium.passthru.sandboxExecutableName or "__chromium-suid-sandbox";
  browserSpecs = {
    chromium = {
      packageName = pkgs.chromium.pname or "chromium";
      source = "${pkgs.chromium.sandbox}/bin/${chromiumSandboxExecutableName}";
      helperName = chromiumSandboxExecutableName;
      commands = [
        "chromium"
        "chromium-browser"
      ];
    };
    google-chrome = {
      packageName = pkgs.google-chrome.pname or "google-chrome";
      source = "${pkgs.google-chrome}/share/google/chrome/chrome-sandbox";
      helperName = "google-chrome-suid-sandbox";
      commands = [
        "google-chrome"
        "google-chrome-stable"
      ];
    };
    microsoft-edge = {
      packageName = pkgs.microsoft-edge.pname or "microsoft-edge";
      source = "${pkgs.microsoft-edge}/share/microsoft/msedge/msedge-sandbox";
      helperName = "microsoft-edge-suid-sandbox";
      commands = [
        "microsoft-edge"
        "microsoft-edge-stable"
      ];
    };
  };
  enabledBrowsers = lib.optionals cfg.enable browserOrder;
  helperSpecs = map (
    browser:
    let
      spec = browserSpecs.${browser};
    in
    spec
    // {
      inherit browser;
      targetPath = "${wrapperHelperRoot}/${spec.helperName}";
      runtimePath = "${stableHelperRoot}/${spec.helperName}";
    }
  ) enabledBrowsers;
  preinstalledBrowsers = lib.unique cfg.preinstalledBrowsers;
  preinstalledShimSpecs = lib.concatMap (
    browser:
    let
      spec = browserSpecs.${browser};
    in
    map (command: {
      inherit browser command;
      helperPath = "${stableHelperRoot}/${spec.helperName}";
      path = "${user.home}/.local/share/devcontainer/bin/${command}";
    }) spec.commands
  ) (lib.optionals cfg.enable preinstalledBrowsers);
  marker = "devcontainers.nix browser sandbox shim";
  shimText =
    {
      command,
      helperPath,
      ...
    }:
    ''
      #!/usr/bin/env bash
      # ${marker}
      set -euo pipefail

      browser_command=${lib.escapeShellArg command}
      sandbox_helper=${lib.escapeShellArg helperPath}

      filter_path_without_dir() {
        local remove="$1"
        local old_ifs="$IFS"
        local entry
        local filtered=""

        IFS=:
        for entry in ''${PATH:-}; do
          if [ -z "$entry" ] || [ "$entry" = "$remove" ]; then
            continue
          fi
          if [ -z "$filtered" ]; then
            filtered="$entry"
          else
            filtered="$filtered:$entry"
          fi
        done
        IFS="$old_ifs"
        printf '%s\n' "$filtered"
      }

      patch_chrome_devel_sandbox_exports() {
        local wrapper="$1"
        local first_line
        local line
        local patch_dir
        local patched_wrapper
        local replaced=false

        if ! IFS= read -r first_line < "$wrapper"; then
          return 1
        fi
        case "$first_line" in
          "#!"*) ;;
          *) return 1 ;;
        esac

        if [ -n "''${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
          patch_dir="$XDG_RUNTIME_DIR/devcontainer-browser-shims"
        else
          patch_dir="''${TMPDIR:-/tmp}/devcontainer-browser-shims-$UID"
        fi

        mkdir -p "$patch_dir"
        patched_wrapper="$patch_dir/$browser_command"
        : > "$patched_wrapper"

        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in
            *"export CHROME_DEVEL_SANDBOX="*)
              printf 'export CHROME_DEVEL_SANDBOX=%q\n' "$sandbox_helper" >> "$patched_wrapper"
              replaced=true
              ;;
            *)
              printf '%s\n' "$line" >> "$patched_wrapper"
              ;;
          esac
        done < "$wrapper"

        if [ "$replaced" = true ]; then
          chmod 0700 "$patched_wrapper"
          printf '%s\n' "$patched_wrapper"
          return 0
        fi

        return 1
      }

      shim_dir="$(CDPATH= cd -- "$(dirname -- "''${BASH_SOURCE[0]}")" && pwd -P)"
      filtered_path="$(filter_path_without_dir "$shim_dir")"
      if ! real_browser="$(PATH="$filtered_path" command -v "$browser_command" 2>/dev/null)"; then
        printf 'devcontainers.nix: browser command not installed: %s\n' "$browser_command" >&2
        exit 127
      fi

      if [ ! -x "$sandbox_helper" ]; then
        printf 'devcontainers.nix: browser sandbox helper is not executable: %s\n' "$sandbox_helper" >&2
        exit 126
      fi

      case "$browser_command" in
        chromium | chromium-browser)
          if patched_browser="$(patch_chrome_devel_sandbox_exports "$real_browser")"; then
            export CHROME_DEVEL_SANDBOX="$sandbox_helper"
            exec bash -e "$patched_browser" "$@"
          fi
          ;;
      esac

      export CHROME_DEVEL_SANDBOX="$sandbox_helper"
      exec "$real_browser" "$@"
    '';
  writeShim = shim: pkgs.writeText "devcontainer-browser-shim-${shim.command}" (shimText shim);
  copyHelperCommands = lib.concatMapStringsSep "\n" (helper: ''
    test -x ${helper.source}
    install -D -m 0755 ${helper.source} "$out${helper.targetPath}"
    install -D -m 0755 ${helper.source} "$out${helper.runtimePath}"
  '') helperSpecs;
  copyShimCommands = lib.concatMapStringsSep "\n" (shim: ''
    install -D -m 0755 ${writeShim shim} "$out${shim.path}"
  '') preinstalledShimSpecs;
  root = pkgs.runCommand "${config.devcontainer.image.name}-customization-root" { } ''
    mkdir -p "$out"
    cp -a ${compiledFilesystem.root}/. "$out/"
    chmod -R u+w "$out"
    ${copyHelperCommands}
    ${copyShimCommands}
  '';
  remapFilesystemPerm =
    perm:
    perm
    // {
      path = root;
      regex = builtins.replaceStrings [ "^${compiledFilesystem.root}" ] [ "^${root}" ] perm.regex;
    };
  filesystemPerms = map remapFilesystemPerm compiledFilesystem.perms;
  helperPerms = lib.concatMap (
    helper:
    map
      (helperPath: {
        path = root;
        regex = "^${root}${helperPath}$";
        mode = "4755";
        uid = 0;
        gid = 0;
        uname = "root";
        gname = "root";
      })
      [
        helper.targetPath
        helper.runtimePath
      ]
  ) helperSpecs;
  helperDirectoryPerms =
    let
      dirs = [
        "/run/wrappers"
        "/run/wrappers/bin"
        "/opt"
        "/opt/devcontainer"
        stableHelperRoot
      ];
    in
    lib.optionals cfg.enable (
      map (dir: {
        path = root;
        regex = "^${root}${dir}$";
        mode = "0755";
        uid = 0;
        gid = 0;
        uname = "root";
        gname = "root";
      }) dirs
    );
  shimDirectoryPerms =
    let
      dirs = [
        "${user.home}/.local"
        "${user.home}/.local/share"
        "${user.home}/.local/share/devcontainer"
        "${user.home}/.local/share/devcontainer/bin"
      ];
    in
    lib.optionals (preinstalledShimSpecs != [ ]) (
      map (dir: {
        path = root;
        regex = "^${root}${dir}$";
        mode = "0755";
        uid = user.uid;
        gid = user.gid;
        uname = user.name;
        gname = user.group;
      }) dirs
    );
  shimPerms = map (shim: {
    path = root;
    regex = "^${root}${shim.path}$";
    mode = "0755";
    uid = user.uid;
    gid = user.gid;
    uname = user.name;
    gname = user.group;
  }) preinstalledShimSpecs;
in
{
  inherit root;
  perms = filesystemPerms ++ helperDirectoryPerms ++ helperPerms ++ shimDirectoryPerms ++ shimPerms;
  report = {
    enabled = cfg.enable;
    helperRoot = lib.optionalString cfg.enable wrapperHelperRoot;
    runtimeHelperRoot = lib.optionalString cfg.enable stableHelperRoot;
    helpers = map (helper: {
      inherit (helper)
        browser
        runtimePath
        targetPath
        ;
      source = builtins.unsafeDiscardStringContext helper.source;
      package = helper.packageName;
      mode = "4755";
      owner = "root:root";
    }) helperSpecs;
    preinstalledBrowsers = preinstalledBrowsers;
    shims = map (shim: {
      inherit (shim)
        browser
        command
        path
        helperPath
        ;
      managed = true;
      marker = marker;
    }) preinstalledShimSpecs;
  };
}
