{
  pkgs,
  lib,
  timeoutScale ? (
    let
      raw = builtins.getEnv "DEVCONTAINERS_NIX_E2E_TIMEOUT_SCALE";
    in
    if raw == "" then 8 else builtins.fromJSON raw
  ),
}:

let
  timeoutScaleValue =
    assert lib.assertMsg (
      builtins.isInt timeoutScale && timeoutScale >= 1
    ) "tests/e2e/vscode-gui.nix: timeoutScale must be an integer >= 1";
    timeoutScale;
  scaledTimeout = seconds: seconds * timeoutScaleValue;

  sessionNames = map (entry: entry.name) sessionEntries;

  vscodeWithExtensions = pkgs.vscode-with-extensions.override {
    vscode = pkgs.vscode;
    vscodeExtensions = [
      pkgs.vscode-extensions.ms-vscode-remote.remote-containers
    ];
  };

  remoteContainersExtension = pkgs.vscode-extensions.ms-vscode-remote.remote-containers;
  remoteContainersPath = "${remoteContainersExtension}/share/vscode/extensions/ms-vscode-remote.remote-containers";
  devcontainerSpecCli = "${remoteContainersPath}/dev-containers-user-cli/dist/spec-node/devContainersSpecCLI.js";

  inherit (pkgs.vscode.passthru) rev vscodeServer;

  indentPython =
    prefix: text:
    lib.concatStringsSep "\n" (
      map (line: prefix + line) (builtins.filter (line: line != "") (lib.splitString "\n" text))
    );

  vscodeServerTarball =
    pkgs.runCommand "vscode-server-${rev}-linux-x64.tar.gz"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        server_dir="$TMPDIR/vscode-server-linux-x64"
        mkdir -p "$server_dir"
        cp -a ${vscodeServer}/. "$server_dir"/

        # VS Code untars the cached server into a temporary directory and then
        # renames that single top-level directory to the commit hash.
        find "$server_dir" -type d -exec chmod u+rwx,go+rx {} +
        find "$server_dir" -type f -exec chmod u+rw,go+r {} +
        find "$server_dir" -type f -perm -0100 -exec chmod a+x {} +

        tar --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
          -czf "$out" -C "$TMPDIR" vscode-server-linux-x64
      '';

  commonMachineModule =
    {
      pkgs,
      lib,
      ...
    }:
    {
      virtualisation = {
        diskSize = 65536;
        memorySize = 8192;
        cores = 4;
        qemu.options = [
          # A TCG fallback makes Docker image import too slow to be useful here.
          "-machine accel=kvm"
        ];
        docker = {
          enable = true;
          autoPrune.enable = true;
        };
      };

      networking.firewall.enable = false;

      users.users.alice = {
        isNormalUser = true;
        uid = 1000;
        extraGroups = [
          "docker"
          "wheel"
        ];
        password = "alice";
      };
      security.sudo.wheelNeedsPassword = false;

      environment.systemPackages = [
        vscodeWithExtensions
        pkgs.coreutils
        pkgs.docker
        pkgs.findutils
        pkgs.gnutar
        pkgs.gzip
        pkgs.glib
        pkgs.jq
        pkgs.nodejs
        pkgs.procps
        pkgs.xauth
        pkgs.xdotool
        pkgs.xwininfo
      ];

      fonts.packages = with pkgs; [
        dejavu_fonts
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
      ];

      services.dbus.enable = true;

      systemd.tmpfiles.rules = [
        "d /tmp/e2e-artifacts 0755 root root - -"
      ];

      system.activationScripts.vscodeGuiE2eFixture = ''
        install -d -o alice -g users -m 0755 /home/alice/workspace/.devcontainer
        install -D -o alice -g users -m 0644 /etc/devcontainers-nix-e2e/devcontainer.json \
          /home/alice/workspace/.devcontainer/devcontainer.json
        install -D -o alice -g users -m 0644 /etc/devcontainers-nix-e2e/settings.json \
          /home/alice/.config/Code/User/settings.json
        install -d -o alice -g users -m 0755 \
          /home/alice/.cache/vscode-server-downloads/${rev}
        install -D -o alice -g users -m 0644 ${vscodeServerTarball} \
          /home/alice/.cache/vscode-server-downloads/${rev}/vscode-server-linux-x64.tar.gz
        chown -R alice:users /home/alice/workspace /home/alice/.config /home/alice/.cache
      '';
    };

  sessionEntries = [
    {
      name = "x11-i3";
      value = {
        backend = "x11";
        docs = {
          backend = "X11";
          desktop = "LightDM auto-login with i3";
        };
        codeFlags = [
          "--disable-gpu"
        ];
        waitForSession = ''
          machine.wait_for_x()
          machine.wait_for_file("/home/alice/.Xauthority")
          machine.succeed("xauth merge /home/alice/.Xauthority")
        '';
        waitForWindow = ''
          wait_for_vscode_window(timeout=scaled_timeout(90))
        '';
        module =
          {
            lib,
            pkgs,
            ...
          }:
          {
            services.xserver.enable = true;
            services.xserver.displayManager.lightdm.enable = true;
            services.xserver.windowManager.i3.enable = true;
            services.displayManager = {
              autoLogin = {
                enable = true;
                user = "alice";
              };
              defaultSession = lib.mkForce "none+i3";
            };
          };
      };
    }

    {
      name = "x11-xfce";
      value = {
        backend = "x11";
        docs = {
          backend = "X11";
          desktop = "LightDM auto-login with Xfce";
        };
        codeFlags = [
          "--disable-gpu"
        ];
        waitForSession = ''
          machine.wait_for_x()
          machine.wait_for_file("/home/alice/.Xauthority")
          machine.succeed("xauth merge /home/alice/.Xauthority")
        '';
        waitForWindow = ''
          wait_for_vscode_window(timeout=scaled_timeout(90))
        '';
        module = { lib, ... }: {
          services.xserver.enable = true;
          services.xserver.displayManager.lightdm.enable = true;
          services.xserver.desktopManager.xfce.enable = true;
          services.displayManager = {
            autoLogin = {
              enable = true;
              user = "alice";
            };
            defaultSession = lib.mkDefault "xfce";
          };
        };
      };
    }

    {
      name = "wayland-sway";
      value = {
        backend = "wayland";
        docs = {
          backend = "Wayland";
          desktop = "tty auto-login with Sway";
        };
        codeFlags = [
          "--enable-features=UseOzonePlatform"
          "--ozone-platform=wayland"
          "--disable-gpu"
        ];
        waitForSession = ''
          machine.wait_for_unit("multi-user.target")
          machine.wait_until_succeeds("test -S /run/user/1000/wayland-0 -o -S /run/user/1000/wayland-1", timeout=scaled_timeout(120))
          machine.wait_for_file("/tmp/sway-ipc.sock", timeout=scaled_timeout(120))
        '';
        waitForWindow = ''
          machine.wait_until_succeeds(
              "su - alice -c 'SWAYSOCK=/tmp/sway-ipc.sock swaymsg -t get_tree | jq -e \".. | objects | select((.name? // \\\"\\\") | test(\\\"workspace.*Visual Studio Code|Visual Studio Code.*workspace\\\"; \\\"i\\\"))\" >/dev/null'",
              timeout=scaled_timeout(180),
          )
        '';
        module = { pkgs, ... }: {
          services.getty.autologinUser = "alice";
          programs.sway.enable = true;
          environment.systemPackages = [
            pkgs.sway
            pkgs.wayland-utils
          ];
          environment.variables = {
            SWAYSOCK = "/tmp/sway-ipc.sock";
            WLR_RENDERER = "pixman";
          };
          programs.bash.loginShellInit = ''
            if [ "$(tty)" = "/dev/tty1" ]; then
              set -e
              mkdir -p ~/.config/sway
              sed s/Mod4/Mod1/ /etc/sway/config > ~/.config/sway/config
              sway --validate
              exec sway
            fi
          '';
          virtualisation.qemu.options = [
            "-vga none -device virtio-gpu-pci"
          ];
        };
      };
    }

    {
      name = "wayland-kde";
      value = {
        backend = "wayland";
        docs = {
          backend = "Wayland";
          desktop = "SDDM auto-login with Plasma";
        };
        codeFlags = [
          "--enable-features=UseOzonePlatform"
          "--ozone-platform=wayland"
          "--disable-gpu"
        ];
        waitForSession = ''
          machine.wait_for_unit("display-manager.service")
          machine.wait_until_succeeds("test -S /run/user/1000/wayland-0 -o -S /run/user/1000/wayland-1", timeout=scaled_timeout(180))
          machine.wait_until_succeeds("su -l alice --shell /bin/sh -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active --quiet plasma-workspace-wayland.target'", timeout=scaled_timeout(180))
          machine.wait_until_succeeds("su -l alice --shell /bin/sh -c 'XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user is-active --quiet graphical-session.target'", timeout=scaled_timeout(180))
        '';
        waitForWindow = ''
          machine.wait_until_succeeds(
              as_alice(
                  "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
                  "XDG_RUNTIME_DIR=/run/user/1000 "
                  "kdotool search --name 'Visual Studio Code' "
                  "getwindowname %@ 2>/dev/null "
                  "| grep -E 'workspace.*Visual Studio Code|Visual Studio Code.*workspace'"
              ),
              timeout=scaled_timeout(180),
          )
        '';
        module =
          {
            lib,
            pkgs,
            ...
          }:
          {
            services.displayManager = {
              sddm = {
                enable = true;
                wayland.enable = true;
              };
              autoLogin = {
                enable = true;
                user = "alice";
              };
              defaultSession = lib.mkForce "plasma";
            };
            services.desktopManager.plasma6.enable = true;
            environment.systemPackages = [
              pkgs.kdotool
            ];
            virtualisation.qemu.options = [
              "-vga none -device virtio-gpu-pci"
            ];
          };
      };
    }
  ];
  sessions = lib.listToAttrs (map (entry: lib.nameValuePair entry.name entry.value) sessionEntries);
  sessionDocs = map (entry: {
    inherit (entry) name;
    inherit (entry.value.docs) backend desktop;
  }) sessionEntries;

  mkVscodeGuiTest =
    {
      imageName,
      image,
      session,
    }:
    let
      sessionConfig = sessions.${session} or (throw "Unknown VS Code GUI E2E session: ${session}");
      expectedBackend = sessionConfig.backend;
      imageRef = "${image.oci.imageName}:${image.oci.imageTag}";
      codeFlags = lib.concatStringsSep " " (
        [
          "--new-window"
          "--disable-workspace-trust"
          "--disable-telemetry"
          "--disable-updates"
          "--skip-release-notes"
          "--password-store=basic"
        ]
        ++ sessionConfig.codeFlags
      );

      workspacePath = "/home/alice/workspace";
      postAttachMarkerName = "E2E-READY-MARKER.txt";
      postAttachMarkerEncoded = "RTJFLVJFQURZLU1BUktFUi50eHQ=";
      terminalProbePath = "/tmp/e2e-vscode-terminal-probe.txt";
      terminalProbeUserPath = "/tmp/e2e-vscode-terminal-user.txt";
      terminalProbePwdPath = "/tmp/e2e-vscode-terminal-pwd.txt";
      terminalProbeValue = "E2E_TERMINAL_OK";
      waitForSessionScript = indentPython "    " sessionConfig.waitForSession;
      waitForWindowScript = indentPython "    " sessionConfig.waitForWindow;
      devcontainerJson = pkgs.writeText "devcontainer-${imageName}-${session}.json" (
        builtins.toJSON {
          name = "devcontainers-nix-e2e-${imageName}";
          image = imageRef;
          workspaceFolder = "/workspaces/workspace";
          updateRemoteUserUID = false;
          postAttachCommand = "sh -lc 'n=$(printf %s ${postAttachMarkerEncoded} | base64 -d); : > \"/workspaces/workspace/$n\"; printf %s \"/workspaces/workspace/$n\" > /tmp/e2e-postattach-marker-path'";
        }
      );
      vscodeSettings = pkgs.writeText "vscode-settings-${imageName}-${session}.json" (
        builtins.toJSON {
          "dev.containers.cacheVolume" = false;
          "dev.containers.copyGitConfig" = false;
          "dev.containers.defaultExtensions" = [ ];
          "dev.containers.dockerCredentialHelper" = false;
          "dev.containers.dockerPath" = "docker";
          "dev.containers.dockerSocketPath" = "/var/run/docker.sock";
          "dev.containers.gpuAvailability" = "none";
          "dev.containers.logLevel" = "trace";
          "dev.containers.mountWaylandSocket" = true;
          "chat.commandCenter.enabled" = false;
          "chat.detectParticipant.enabled" = false;
          "chat.disableAIFeatures" = true;
          "chat.titleBar.signIn.enabled" = false;
          "extensions.autoCheckUpdates" = false;
          "extensions.autoUpdate" = false;
          "extensions.ignoreRecommendations" = true;
          "remote.serverDownloadBaseUrl" = "http://127.0.0.1:9/vscode-server-cache-miss";
          "remote.serverDownloadFolder" = "/home/alice/.cache/vscode-server-downloads";
          "security.workspace.trust.emptyWindow" = false;
          "security.workspace.trust.enabled" = false;
          "security.workspace.trust.startupPrompt" = "never";
          "telemetry.enableTelemetry" = false;
          "telemetry.telemetryLevel" = "off";
          "update.mode" = "none";
          "window.restoreWindows" = "none";
          "window.zoomLevel" = 0;
          "workbench.startupEditor" = "none";
          "workbench.welcomePage.walkthroughs.openOnInstall" = false;
        }
      );
      dockerArchive =
        pkgs.runCommand "e2e-vscode-${imageName}-${session}-docker-archive.tar"
          {
            nativeBuildInputs = [
              pkgs.skopeo-nix2container
            ];
          }
          ''
            image_ref=${lib.escapeShellArg imageRef}
            archive="$TMPDIR/image.tar"
            tmpdir="$TMPDIR/skopeo"
            mkdir -p "$tmpdir"

            skopeo --tmpdir "$tmpdir" --insecure-policy copy \
              ${lib.escapeShellArg "nix:${image.oci}"} \
              "docker-archive:$archive:$image_ref"

            test -s "$archive"
            install -D -m 0644 "$archive" "$out"
          '';
      verificationScript = pkgs.writeShellScript "verify-vscode-devcontainer-${imageName}-${session}" ''
                set -euo pipefail

                expected_backend=${lib.escapeShellArg expectedBackend}
                post_attach_marker=${lib.escapeShellArg "/workspaces/workspace/${postAttachMarkerName}"}
                terminal_probe_path=${lib.escapeShellArg terminalProbePath}
                terminal_probe_user_path=${lib.escapeShellArg terminalProbeUserPath}
                terminal_probe_pwd_path=${lib.escapeShellArg terminalProbePwdPath}
                terminal_probe_value=${lib.escapeShellArg terminalProbeValue}
                smoke_plan=/tmp/e2e-smoke-test-plan.json
                log=/tmp/e2e-container-verification.log
                : >"$log"
                exec > >(tee -a "$log") 2>&1

                require() {
                  "$@"
                }

                require test "$(id -un)" = "vscode"
                require test "$HOME" = "/home/vscode"
                require test "''${XDG_RUNTIME_DIR:-}" = "/run/user/1000"
                require test -d /workspaces/workspace
                require test -f "$post_attach_marker"
                require test -f "$terminal_probe_path"
                require test -f "$terminal_probe_user_path"
                require test -f "$terminal_probe_pwd_path"
                require test "$(cat "$terminal_probe_path")" = "$terminal_probe_value"
                require test "$(cat "$terminal_probe_user_path")" = "vscode"
                require test "$(cat "$terminal_probe_pwd_path")" = "/workspaces/workspace"
                require test -f /usr/share/devcontainer/tasks.json
                require test -f /usr/share/devcontainer/vscode/extensions-index.json

                nix --version
                devpkg list >/dev/null
                devcontainer-task-runner status

                require grep -qx done /home/vscode/.local/state/devcontainer/tasks/status/xdg-dirs.status
                require grep -qx done /home/vscode/.local/state/devcontainer/tasks/status/vscode-extension-projection.status

                gui_env_status=/tmp/e2e-gui-env-status.txt
                gui_env_log="''${XDG_STATE_HOME:-$HOME/.local/state}/devcontainer/tasks/logs/gui-env-refresh.log"
                require test -f "$gui_env_log"
                cp "$gui_env_log" "$gui_env_status"
                cat "$gui_env_status"
                require grep -Fx "backend=$expected_backend" /tmp/e2e-gui-env-status.txt
                require test -f /run/user/1000/devcontainer-gui-env.sh
                # The postStart task writes this shell fragment with VS Code's remote env.
                # shellcheck disable=SC1091
                . /run/user/1000/devcontainer-gui-env.sh

                case "$expected_backend" in
                  x11)
                    if ! grep -E '^(display|remote_containers_display)=.+' "$gui_env_status" >/dev/null; then
                      echo "gui-env-refresh log must contain DISPLAY or REMOTE_CONTAINERS_DISPLAY for X11 sessions" >&2
                      exit 1
                    fi
                    require grep -E "XDG_SESSION_TYPE=.*x11" /run/user/1000/devcontainer-gui-env.sh
                    ;;
                  wayland)
                    require test -n "''${WAYLAND_DISPLAY:-}"
                    case "$WAYLAND_DISPLAY" in
                      /*) wayland_socket="$WAYLAND_DISPLAY" ;;
                      *) wayland_socket="''${XDG_RUNTIME_DIR:-/run/user/1000}/$WAYLAND_DISPLAY" ;;
                    esac
                    require test -S "$wayland_socket"
                    require grep -Fx "wayland_socket_valid=1" /tmp/e2e-gui-env-status.txt
                    require grep -E "XDG_SESSION_TYPE=.*wayland" /run/user/1000/devcontainer-gui-env.sh
                    require grep -E "NIXOS_OZONE_WL=.*1" /run/user/1000/devcontainer-gui-env.sh
                    ;;
                  *)
                    echo "unsupported expected backend: $expected_backend" >&2
                    exit 1
                    ;;
        esac

        require test -f "$smoke_plan"
        jq -c '.tests[] | select(.tags | index("e2e-baseline"))' "$smoke_plan" | while IFS= read -r test_case; do
          id="$(printf '%s' "$test_case" | jq -r '.id')"
          mapfile -t command_parts < <(printf '%s' "$test_case" | jq -r '.command[]')
          timeout_seconds="$(printf '%s' "$test_case" | jq -r '(.timeoutSeconds // 30) * ${toString timeoutScaleValue}')"
          if [ "''${#command_parts[@]}" -eq 0 ]; then
            echo "skip smoke $id"
            continue
          fi

          echo "==> smoke $id"
          printf 'command='
          printf '%q ' "''${command_parts[@]}"
          printf '\n'
          timeout "$timeout_seconds" "''${command_parts[@]}"
        done
      '';
    in
    pkgs.testers.runNixOSTest {
      name = "e2e-vscode-${imageName}-${session}";
      skipTypeCheck = true;
      enableOCR = true;
      # The base values below are tuned for a fast local host.  The default
      # scale is the CI/slow-builder profile.  Local fast runs can use:
      # DEVCONTAINERS_NIX_E2E_TIMEOUT_SCALE=1 nix build --impure .#...
      globalTimeout = scaledTimeout 375;

      meta.timeout = scaledTimeout 375;

      nodes.machine =
        { ... }:
        {
          imports = [
            commonMachineModule
            sessionConfig.module
          ];

          environment.etc = {
            "devcontainers-nix-e2e/devcontainer.json".source = devcontainerJson;
            "devcontainers-nix-e2e/settings.json".source = vscodeSettings;
          };
        };

      testScript = ''
        import fcntl
        import os
        import re
        import shlex
        import time

        IMAGE_REF = ${builtins.toJSON imageRef}
        WORKSPACE = ${builtins.toJSON workspacePath}
        POST_ATTACH_MARKER_NAME = ${builtins.toJSON postAttachMarkerName}
        TERMINAL_PROBE_PATH = ${builtins.toJSON terminalProbePath}
        TERMINAL_PROBE_USER_PATH = ${builtins.toJSON terminalProbeUserPath}
        TERMINAL_PROBE_PWD_PATH = ${builtins.toJSON terminalProbePwdPath}
        TERMINAL_PROBE_VALUE = ${builtins.toJSON terminalProbeValue}
        BACKEND = ${builtins.toJSON expectedBackend}
        SESSION = ${builtins.toJSON session}
        CODE_FLAGS = ${builtins.toJSON codeFlags}
        SPEC_CLI = ${builtins.toJSON devcontainerSpecCli}
        DOCKER_ARCHIVE = ${builtins.toJSON "${dockerArchive}"}
        SMOKE_PLAN = ${builtins.toJSON "${image.smoke}"}
        VERIFY_SCRIPT = ${builtins.toJSON "${verificationScript}"}
        TIMEOUT_SCALE = ${builtins.toJSON timeoutScaleValue}


        class DevcontainerFatalError(Exception):
            pass


        def scaled_timeout(seconds):
            return max(1, int(seconds * TIMEOUT_SCALE))


        def scaled_delay(seconds):
            return max(0, seconds * TIMEOUT_SCALE)


        def q(value):
            return shlex.quote(str(value))


        def as_alice(command):
            return "su - alice -c " + q(command)


        def host_kvm_diagnostics():
            details = [
                f"uid={os.getuid()}",
                f"euid={os.geteuid()}",
                f"groups={os.getgroups()}",
            ]
            try:
                st = os.stat("/dev/kvm")
                details.append(
                    "/dev/kvm "
                    f"mode={oct(st.st_mode & 0o7777)} "
                    f"uid={st.st_uid} gid={st.st_gid} "
                    f"rdev={os.major(st.st_rdev)}:{os.minor(st.st_rdev)}"
                )
            except OSError as error:
                details.append(f"/dev/kvm stat failed: errno={error.errno} {error.strerror}")

            for path in (
                "/sys/module/kvm_intel/parameters/nested",
                "/sys/module/kvm_amd/parameters/nested",
            ):
                try:
                    with open(path) as file:
                        details.append(f"{path}={file.read().strip()}")
                except FileNotFoundError:
                    pass
                except OSError as error:
                    details.append(f"{path} read failed: errno={error.errno} {error.strerror}")

            try:
                with open("/proc/cpuinfo") as file:
                    cpuinfo = file.read()
                flags_line = next(
                    (line for line in cpuinfo.splitlines() if line.startswith("flags")),
                    "",
                )
                flags = flags_line.split(":", 1)[1].split() if ":" in flags_line else []
                details.append(
                    "cpu flags: "
                    f"vmx={'vmx' in flags} "
                    f"svm={'svm' in flags} "
                    f"hypervisor={'hypervisor' in flags}"
                )
            except OSError as error:
                details.append(f"/proc/cpuinfo read failed: errno={error.errno} {error.strerror}")

            return "; ".join(details)


        def assert_host_kvm_available():
            kvm_get_api_version = 0xAE00
            kvm_create_vm = 0xAE01
            try:
                kvm_fd = os.open("/dev/kvm", os.O_RDWR | os.O_CLOEXEC)
            except FileNotFoundError as error:
                raise RuntimeError(
                    "VS Code GUI E2E requires host KVM at /dev/kvm. "
                    "The test intentionally does not fall back to TCG because "
                    "Docker image import is too slow in software emulation. "
                    f"Diagnostics: {host_kvm_diagnostics()}"
                ) from error
            except PermissionError as error:
                raise RuntimeError(
                    "VS Code GUI E2E requires read/write access to /dev/kvm. "
                    "Run it on a builder whose Nix build user can use KVM. "
                    f"Diagnostics: {host_kvm_diagnostics()}"
                ) from error

            try:
                version = fcntl.ioctl(kvm_fd, kvm_get_api_version, 0)
                if version != 12:
                    raise RuntimeError(f"unexpected KVM API version: {version}")
                vm_fd = fcntl.ioctl(kvm_fd, kvm_create_vm, 0)
                os.close(vm_fd)
            except OSError as error:
                raise RuntimeError(
                    "VS Code GUI E2E requires usable host KVM, but KVM_CREATE_VM failed "
                    f"with errno={error.errno} {error.strerror}. "
                    "This usually means nested virtualization is disabled or /dev/kvm "
                    "is not usable inside the Nix build environment. It can also happen "
                    "when another hypervisor, such as VirtualBox, is currently holding KVM; "
                    "stop those VMs/processes and retry. "
                    f"Diagnostics: {host_kvm_diagnostics()}"
                ) from error
            finally:
                os.close(kvm_fd)


        def session_env():
            common = (
                "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
                "XDG_RUNTIME_DIR=/run/user/1000 "
            )
            if BACKEND == "x11":
                return common + "DISPLAY=:0 XAUTHORITY=/home/alice/.Xauthority XDG_SESSION_TYPE=x11 "
            return (
                common
                + "WAYLAND_DISPLAY=$(basename \"$(find /run/user/1000 -maxdepth 1 -type s -name 'wayland-*' | sort | head -n1)\") "
                + "XDG_SESSION_TYPE=wayland NIXOS_OZONE_WL=1 "
            )


        def e2e_log(message):
            machine.log(f"e2e: {message}")


        def wait_for_local_devcontainers_logs(timeout=scaled_timeout(60)):
            machine.wait_until_succeeds(
                "bash -lc "
                + q(
                    "compgen -G "
                    "'/home/alice/.config/Code/logs/*/window*/exthost/"
                    "ms-vscode-remote.remote-containers/remoteContainers-*.log' "
                    ">/dev/null"
                ),
                timeout=timeout,
            )


        def screen_text():
            try:
                return "\n".join(machine.get_screen_text_variants())
            except Exception as error:
                machine.log(f"OCR read failed: {error}")
                return ""


        def save_screen_text(text):
            write_guest_file("/tmp/e2e-vscode-screen-ocr.txt", text)


        def vscode_ocr_failure(text):
            match = re.search(r"\bRetry\b|An error occurred", text, re.I)
            return match.group(0) if match else ""


        def vscode_ocr_loading(text):
            return bool(re.search(r"Connecting\s+to\s+Dev\s+Container", text, re.I))


        def vscode_ocr_ready_signals(text):
            compact = re.sub(r"\s+", " ", text)
            explorer_ready = bool(
                re.search(r"\bEXPLORER\b", compact, re.I)
                and re.search(r"WORKSPACE.*DEV\s+CONTAINER", compact, re.I)
                and re.search(r"\.?devcontainer", compact, re.I)
            )
            terminal_done = bool(
                re.search(
                    r"Done\.\s*Press\s+any\s+key\s+to\s+close\s+the\s+terminal",
                    compact,
                    re.I,
                )
            )
            return explorer_ready, terminal_done


        def vscode_ocr_ready(text):
            explorer_ready, terminal_done = vscode_ocr_ready_signals(text)
            return terminal_done or explorer_ready


        def vscode_ocr_postattach_marker_ready(text):
            normalized_text = re.sub(r"[^A-Z0-9]+", "", text.upper())
            normalized_marker = re.sub(r"[^A-Z0-9]+", "", POST_ATTACH_MARKER_NAME.upper())
            normalized_marker_stem = re.sub(
                r"[^A-Z0-9]+",
                "",
                POST_ATTACH_MARKER_NAME.rsplit(".", 1)[0].upper(),
            )
            return normalized_marker in normalized_text or normalized_marker_stem in normalized_text


        def dismiss_vscode_overlays():
            for _ in range(3):
                machine.send_key("esc")
                machine.sleep(1)


        def collect_artifacts(container_id=""):
            machine.execute("mkdir -p /tmp/e2e-artifacts", timeout=scaled_timeout(30))
            machine.execute("docker ps -a > /tmp/e2e-artifacts/docker-ps.txt 2>&1 || true", timeout=scaled_timeout(30))
            machine.execute("docker images > /tmp/e2e-artifacts/docker-images.txt 2>&1 || true", timeout=scaled_timeout(30))
            if container_id:
                machine.execute(f"docker inspect {q(container_id)} > /tmp/e2e-artifacts/docker-inspect.json 2>&1 || true", timeout=scaled_timeout(30))
                machine.execute(f"docker logs {q(container_id)} > /tmp/e2e-artifacts/container-logs.txt 2>&1 || true", timeout=scaled_timeout(30))
                machine.execute(f"docker cp {q(container_id)}:/home/vscode/.local/state/devcontainer/tasks /tmp/e2e-artifacts/container-tasks 2>/dev/null || true", timeout=scaled_timeout(30))
                machine.execute(f"docker cp {q(container_id)}:/tmp/e2e-task-runner-status.wait.txt /tmp/e2e-artifacts/task-runner-status.wait.txt 2>/dev/null || true", timeout=scaled_timeout(30))
                machine.execute(
                    f"docker exec {q(container_id)} sh -lc "
                    + q(
                        f"for path in {q(TERMINAL_PROBE_PATH)} {q(TERMINAL_PROBE_USER_PATH)} {q(TERMINAL_PROBE_PWD_PATH)}; do "
                        "printf '== %s ==\\n' \"$path\"; "
                        "cat \"$path\" 2>/dev/null || true; "
                        "printf '\\n'; "
                        "done"
                    )
                    + " > /tmp/e2e-artifacts/terminal-probe.txt 2>&1 || true",
                    timeout=scaled_timeout(30),
                )
                machine.execute(
                    f"docker exec {q(container_id)} bash -lc "
                    + q(
                        "for root in "
                        "\"$(printenv VSCODE_AGENT_FOLDER 2>/dev/null || true)\" "
                        "\"$HOME\"/.vscode-server "
                        "\"$HOME\"/.vscode-server-insiders "
                        "\"$HOME\"/.vscodium-server "
                        "\"$HOME\"/.openvscode-server "
                        "\"$HOME\"/.cursor-server "
                        "\"$HOME\"/.windsurf-server "
                        "\"$HOME\"/.*-server; do "
                        "test -d \"$root\" && find \"$root\" -maxdepth 4 "
                        "-mindepth 1 -printf '%y %p\\n'; "
                        "done 2>/dev/null || true"
                    )
                    + " > /tmp/e2e-artifacts/vscode-server-tree.txt 2>&1 || true",
                    timeout=scaled_timeout(30),
                )
            machine.execute("cp -f /home/alice/workspace/.devcontainer/devcontainer.json /tmp/e2e-artifacts/devcontainer.json 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-vscode-window-titles.txt /tmp/e2e-artifacts/vscode-window-titles.txt 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-vscode-window-wait.log /tmp/e2e-artifacts/vscode-window-wait.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-vscode-gui-ready.log /tmp/e2e-artifacts/vscode-gui-ready.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-vscode-screen-ocr.txt /tmp/e2e-artifacts/vscode-screen-ocr.txt 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-command-palette.log /tmp/e2e-artifacts/command-palette.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-terminal-probe.log /tmp/e2e-artifacts/terminal-probe.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-vscode.log /tmp/e2e-artifacts/vscode-launch.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-image-load.log /tmp/e2e-artifacts/image-load.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/devcontainer-cli-up.log /tmp/e2e-artifacts/devcontainer-cli-up.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("cp -f /tmp/e2e-container-verification.log /tmp/e2e-artifacts/container-verification.log 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.execute("tar -C /home/alice/.config/Code -czf /tmp/e2e-artifacts/vscode-logs.tar.gz logs 2>/dev/null || true", timeout=scaled_timeout(60))
            machine.execute(
                "tar -C /home/alice/.config/Code/User/globalStorage "
                "-czf /tmp/e2e-artifacts/devcontainers-global-storage.tar.gz "
                "ms-vscode-remote.remote-containers 2>/dev/null || true",
                timeout=scaled_timeout(60),
            )
            # docker cp preserves root-owned 0600 task files; normalize before exporting artifacts.
            machine.execute("chmod -R u+rwX,go+rX /tmp/e2e-artifacts 2>/dev/null || true", timeout=scaled_timeout(30))
            machine.copy_from_machine("/tmp/e2e-artifacts")


        def load_image():
            machine.wait_for_unit("docker.service")
            machine.wait_until_succeeds("docker info >/dev/null", timeout=scaled_timeout(30))
            machine.succeed(
                f"""
                set -euo pipefail

                log=/tmp/e2e-image-load.log

                : >"$log"
                exec > >(tee -a "$log") 2>&1

                echo "loading image {IMAGE_REF} from prebuilt archive {DOCKER_ARCHIVE}"
                ls -lh {q(DOCKER_ARCHIVE)}
                df -h /nix/store /var/lib/docker || true
                docker system df || true

                echo "loading prebuilt docker archive into daemon"
                timeout {scaled_timeout(180)} docker load -i {q(DOCKER_ARCHIVE)}

                docker image inspect {q(IMAGE_REF)} >/dev/null
                docker system df || true
                """,
                timeout=scaled_timeout(210),
            )
            machine.succeed(f"docker image inspect {q(IMAGE_REF)} >/dev/null", timeout=scaled_timeout(30))


        def launch_vscode():
            launch = (
                f"{session_env()}code {CODE_FLAGS} {q(WORKSPACE)} "
                ">>/tmp/e2e-vscode.log 2>&1 &"
            )
            machine.succeed(as_alice(launch), timeout=scaled_timeout(20))
        ${waitForWindowScript}
            wait_for_local_devcontainers_logs()
            dismiss_vscode_overlays()
            machine.screenshot("vscode-opened")


        def command_palette_log(message):
            machine.execute(
                f"printf '%s\n' {q(message)} >> /tmp/e2e-command-palette.log",
                timeout=scaled_timeout(5),
            )


        def terminal_probe_log(message):
            machine.execute(
                f"printf '%s\n' {q(message)} >> /tmp/e2e-terminal-probe.log",
                timeout=scaled_timeout(5),
            )


        # VS Code's command palette matches case-insensitively and immediately
        # selects the first result. Callers should pass the most specific full
        # command title possible so the first match is the intended command.
        def run_command_palette(command, screenshot_name, open_delay=5, match_delay=5):
            dismiss_vscode_overlays()
            machine.send_key("ctrl-shift-p")
            machine.sleep(scaled_delay(open_delay))
            machine.send_chars(command)
            machine.sleep(scaled_delay(match_delay))
            machine.screenshot(screenshot_name)
            machine.send_key("ret")


        def check_visible_devcontainer_failure():
            text = screen_text()
            save_screen_text(text)
            failure = vscode_ocr_failure(text)
            if failure:
                raise DevcontainerFatalError(
                    "VS Code displayed a Dev Containers failure prompt: " + failure
                )
            return text


        def trigger_reopen_in_container(max_attempts=2, attempt_timeout=scaled_timeout(60)):
            for attempt in range(1, max_attempts + 1):
                command_palette_log(f"attempt {attempt}: opening command palette")
                run_command_palette(
                    "dev containers: rebuild and reopen in container",
                    f"command-palette-reopen-attempt-{attempt}",
                    open_delay=3,
                    match_delay=3,
                )

                deadline = time.monotonic() + attempt_timeout

                while time.monotonic() < deadline:
                    container_id = query_container_id()
                    if container_id:
                        command_palette_log(
                            f"attempt {attempt}: container appeared: {container_id}"
                        )
                        return container_id

                    failure = vscode_devcontainers_failure()
                    if failure:
                        raise DevcontainerFatalError(
                            "VS Code Dev Containers reported a failure while reopening:\n"
                            + failure
                        )

                    machine.sleep(2)

                command_palette_log(
                    f"attempt {attempt}: no container after {attempt_timeout}s"
                )

            raise RuntimeError(
                "VS Code command palette did not start a Dev Container after "
                f"{max_attempts} attempts"
            )


        def query_container_id():
            commands = [
                f"docker ps --filter {q('label=devcontainer.local_folder=' + WORKSPACE)} --format '{{{{.ID}}}}' | head -n1",
                f"docker ps --filter {q('label=devcontainer.config_file=' + WORKSPACE + '/.devcontainer/devcontainer.json')} --format '{{{{.ID}}}}' | head -n1",
                f"docker ps --filter {q('ancestor=' + IMAGE_REF)} --format '{{{{.ID}}}}' | head -n1",
            ]
            for command in commands:
                status, output = machine.execute(command, timeout=scaled_timeout(15))
                if status == 0 and output.strip():
                    return output.strip().splitlines()[0]
            return ""


        def wait_for_container(timeout=scaled_timeout(90)):
            container_id = ""
            deadline = time.monotonic() + timeout

            while time.monotonic() < deadline:
                container_id = query_container_id()
                if container_id:
                    return container_id
                machine.sleep(1)

            machine.log(machine.succeed("docker ps -a --no-trunc", timeout=scaled_timeout(15)))
            raise RuntimeError(f"container did not appear within {timeout} seconds")


        def write_guest_file(path, content):
            machine.execute(f"printf '%s\n' {q(content)} > {q(path)}", timeout=scaled_timeout(5))


        def vscode_window_titles():
            if BACKEND == "x11":
                command = (
                    "DISPLAY=:0 XAUTHORITY=/home/alice/.Xauthority "
                    "xdotool search --onlyvisible --name 'Visual Studio Code' "
                    "getwindowname %@ 2>/dev/null || true"
                )
                status, output = machine.execute(as_alice(command), timeout=scaled_timeout(15))
            elif SESSION == "wayland-sway":
                command = (
                    "SWAYSOCK=/tmp/sway-ipc.sock swaymsg -t get_tree "
                    "| jq -r '.. | objects | .name? // empty' "
                    "| grep -E 'Visual Studio Code|Dev Container|workspace' || true"
                )
                status, output = machine.execute(as_alice(command), timeout=scaled_timeout(15))
            else:
                command = (
                    "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
                    "XDG_RUNTIME_DIR=/run/user/1000 "
                    "kdotool search --name 'Visual Studio Code' "
                    "getwindowname %@ 2>/dev/null || true"
                )
                status, output = machine.execute(as_alice(command), timeout=scaled_timeout(15))
            output = output.strip()
            write_guest_file("/tmp/e2e-vscode-window-titles.txt", output)
            return output


        def wait_for_vscode_window(timeout=scaled_timeout(90)):
            deadline = time.monotonic() + timeout
            last_titles = ""
            last_processes = ""

            while time.monotonic() < deadline:
                titles = vscode_window_titles()
                if titles:
                    last_titles = titles
                _status, processes = machine.execute(
                    as_alice("pgrep -a -f 'code|electron' || true"),
                    timeout=scaled_timeout(5),
                )
                if processes.strip():
                    last_processes = processes.strip()

                if re.search(r"workspace.*Visual Studio Code|Visual Studio Code.*workspace", titles, re.I):
                    return

                machine.sleep(1)

            write_guest_file(
                "/tmp/e2e-vscode-window-wait.log",
                f"titles={last_titles}\nprocesses={last_processes}",
            )
            raise RuntimeError(
                f"VS Code workspace window did not appear within {timeout} seconds; "
                f"last_titles={last_titles!r}; last_processes={last_processes!r}"
            )


        def vscode_gui_title_ready(titles):
            if re.search(r"opening|connecting|reopening|starting|setting up|installing|retry|failed|error|reload", titles, re.I):
                return False

            return bool(
                re.search(
                    r"workspace.*\[Dev Container:[^\]]+\].*Visual Studio Code",
                    titles,
                    re.I,
                )
            )


        def vscode_devcontainers_failure():
            command = r"""
            set +e
            grep -R -H -n -E \
              'Command in container failed:|mv: target .*No such file or directory|Installing VS Code Server.*failed|Failed to connect|Reopen in Container.*failed|Dev Containers?.*(failed|retry|Retry)|An error occurred.*container|Try Again|Retry' \
              /home/alice/.config/Code/logs/*/window*/exthost/ms-vscode-remote.remote-containers/remoteContainers-*.log \
              2>/dev/null
            """
            status, output = machine.execute(command, timeout=scaled_timeout(15))
            output = output.strip()
            if output:
                return output
            return ""


        def vscode_remote_log_ready():
            command = r"""
            set +e
            grep -R -H -n -E \
              'Extension host agent started|Extension host agent listening on|Running Dev Containers CLI: +run-user-commands|"outcome": "success"|"remoteWorkspaceFolder": "/workspaces/workspace"' \
              /home/alice/.config/Code/logs/*/window*/exthost/ms-vscode-remote.remote-containers/remoteContainers-*.log \
              2>/dev/null
            """
            status, output = machine.execute(command, timeout=scaled_timeout(15))
            return status == 0 and bool(output.strip())


        def wait_for_vscode_gui_ready(container_id, timeout=scaled_timeout(90)):
            machine.send_key("ctrl-shift-e")
            deadline = time.monotonic() + timeout
            stable_ready_count = 0
            last_titles = ""
            log_lines = []

            while time.monotonic() < deadline:
                titles = vscode_window_titles()
                title_ready = vscode_gui_title_ready(titles)
                last_titles = titles
                log_ready = vscode_remote_log_ready()
                failure = vscode_devcontainers_failure()
                if failure:
                    raise RuntimeError(
                        "VS Code Dev Containers reported a failure/retry prompt condition:\n"
                        + failure
                    )

                screen = screen_text()
                save_screen_text(screen)
                visible_failure = vscode_ocr_failure(screen)
                if visible_failure:
                    raise RuntimeError(
                        "VS Code displayed a Dev Containers failure prompt: "
                        + visible_failure
                    )

                explorer_ready, terminal_done = vscode_ocr_ready_signals(screen)
                marker_ready = vscode_ocr_postattach_marker_ready(screen)
                loading = vscode_ocr_loading(screen)
                ready = title_ready and marker_ready

                if ready:
                    stable_ready_count += 1
                    log_lines.append(
                        f"ready-sample {stable_ready_count}: "
                        f"title_ready={title_ready} log_ready={log_ready} "
                        f"marker_ready={marker_ready} "
                        f"explorer_ready={explorer_ready} terminal_done={terminal_done} "
                        f"titles={titles}"
                    )
                    if stable_ready_count >= 3:
                        write_guest_file("/tmp/e2e-vscode-gui-ready.log", "\n".join(log_lines))
                        machine.send_key("ctrl-shift-e")
                        machine.sleep(1)
                        machine.screenshot("devcontainer-explorer-ready")
                        return
                else:
                    stable_ready_count = 0
                    log_lines.append(
                        f"not-ready: title_ready={title_ready} "
                        f"log_ready={log_ready} marker_ready={marker_ready} "
                        f"explorer_ready={explorer_ready} "
                        f"terminal_done={terminal_done} loading={loading} titles={titles}"
                    )

                machine.sleep(2)

            write_guest_file("/tmp/e2e-vscode-gui-ready.log", "\n".join(log_lines))
            machine.log(f"last VS Code window titles/processes: {last_titles}")
            raise RuntimeError(
                f"VS Code GUI did not settle into a Dev Container-ready window within {timeout} seconds"
            )


        def read_terminal_probe(container_id):
            command = (
                f"test -f {q(TERMINAL_PROBE_PATH)} "
                f"&& test -f {q(TERMINAL_PROBE_USER_PATH)} "
                f"&& test -f {q(TERMINAL_PROBE_PWD_PATH)} "
                f"&& printf '%s\\n' \"$(cat {q(TERMINAL_PROBE_PATH)})\" "
                f"&& printf '%s\\n' \"$(cat {q(TERMINAL_PROBE_USER_PATH)})\" "
                f"&& printf '%s\\n' \"$(cat {q(TERMINAL_PROBE_PWD_PATH)})\""
            )
            status, output = machine.execute(
                f"docker exec {q(container_id)} sh -lc {q(command)}",
                timeout=scaled_timeout(15),
            )
            lines = output.strip().splitlines()
            return status, lines, output


        def run_vscode_terminal_probe(container_id, timeout=scaled_timeout(60)):
            cleanup = (
                f"rm -f {q(TERMINAL_PROBE_PATH)} "
                f"{q(TERMINAL_PROBE_USER_PATH)} "
                f"{q(TERMINAL_PROBE_PWD_PATH)}"
            )
            machine.execute(
                f"docker exec {q(container_id)} sh -lc {q(cleanup)}",
                timeout=scaled_timeout(15),
            )

            typed_command = (
                f"printf {TERMINAL_PROBE_VALUE} >{TERMINAL_PROBE_PATH}; "
                f"id -un >{TERMINAL_PROBE_USER_PATH}; "
                f"pwd >{TERMINAL_PROBE_PWD_PATH}"
            )
            deadline = time.monotonic() + timeout

            for attempt in range(1, 4):
                if time.monotonic() >= deadline:
                    break

                terminal_probe_log(f"attempt {attempt}: creating VS Code terminal")
                run_command_palette(
                    "terminal: create new terminal in editor area to the side",
                    f"terminal-create-attempt-{attempt}",
                )
                machine.sleep(scaled_delay(5))
                machine.send_chars(typed_command)
                machine.send_key("ret")

                attempt_deadline = min(deadline, time.monotonic() + scaled_timeout(20))
                while time.monotonic() < attempt_deadline:
                    status, lines, output = read_terminal_probe(container_id)
                    if (
                        status == 0
                        and len(lines) >= 3
                        and lines[0] == TERMINAL_PROBE_VALUE
                        and lines[1] == "vscode"
                        and lines[2] == "/workspaces/workspace"
                    ):
                        terminal_probe_log(
                            f"attempt {attempt}: terminal probe succeeded"
                        )
                        machine.screenshot("devcontainer-terminal-probe")
                        return

                    failure = vscode_devcontainers_failure()
                    if failure:
                        raise RuntimeError(
                            "VS Code Dev Containers reported a failure while probing terminal:\n"
                            + failure
                        )

                    if output.strip():
                        terminal_probe_log(
                            f"attempt {attempt}: probe not ready: {output.strip()!r}"
                        )
                    machine.sleep(2)

            status, lines, output = read_terminal_probe(container_id)
            raise RuntimeError(
                "VS Code terminal command did not produce the expected files in the container; "
                f"status={status}; lines={lines!r}; output={output!r}"
            )


        def wait_for_container_lifecycle(container_id, timeout=scaled_timeout(120)):
            readiness_check = """
            set -euo pipefail

            test -d /workspaces/workspace
            test -f /workspaces/workspace/.devcontainer/devcontainer.json
            test -f /usr/share/devcontainer/tasks.json
            test -f /usr/share/devcontainer/vscode/extensions-index.json
            devcontainer-task-runner status > /tmp/e2e-task-runner-status.wait.txt

            for task in gui-env-refresh; do
                status="$HOME/.local/state/devcontainer/tasks/status/$task.status"
                test -f "$status"
                grep -qx done "$status"
            done
            """
            deadline = time.monotonic() + timeout
            last_output = ""

            while time.monotonic() < deadline:
                status, output = machine.execute(
                    f"docker exec {q(container_id)} bash -lc {q(readiness_check)}",
                    timeout=scaled_timeout(15),
                )
                if status == 0:
                    return
                last_output = output.strip()
                failure = vscode_devcontainers_failure()
                if failure:
                    raise RuntimeError(
                        "VS Code Dev Containers reported a fatal connection failure:\n"
                        + failure
                    )
                machine.sleep(2)

            diagnostics = """
            set +e
            echo '== devcontainer-task-runner status =='
            devcontainer-task-runner status
            echo '== task status files =='
            find "$HOME/.local/state/devcontainer/tasks" -maxdepth 3 -type f -print -exec sed -n '1,80p' {} \\;
            echo '== task runner status wait output =='
            cat /tmp/e2e-task-runner-status.wait.txt
            """
            status, output = machine.execute(
                f"docker exec {q(container_id)} bash -lc {q(diagnostics)}",
                timeout=scaled_timeout(30),
            )
            if output.strip():
                machine.log(output)
            raise RuntimeError(
                f"container lifecycle did not become ready within {timeout} seconds; "
                f"last readiness output: {last_output!r}"
            )


        def verify_container(container_id):
            machine.succeed(f"docker cp {q(SMOKE_PLAN)} {q(container_id)}:/tmp/e2e-smoke-test-plan.json", timeout=scaled_timeout(30))
            machine.succeed(f"docker cp {q(VERIFY_SCRIPT)} {q(container_id)}:/tmp/e2e-verify.sh", timeout=scaled_timeout(30))
            status, output = machine.execute(
                f"docker exec {q(container_id)} bash /tmp/e2e-verify.sh",
                timeout=scaled_timeout(180),
            )
            machine.execute(
                f"docker cp {q(container_id)}:/tmp/e2e-container-verification.log /tmp/e2e-container-verification.log 2>/dev/null || true",
                timeout=scaled_timeout(30),
            )
            if status != 0:
                if output.strip():
                    machine.log(output)
                raise RuntimeError(f"container verification failed with exit code {status}")
            machine.screenshot("devcontainer-connected")


        container_id = ""
        try:
            e2e_log("checking host KVM")
            assert_host_kvm_available()
            e2e_log("starting VM")
            start_all()
        ${waitForSessionScript}
            e2e_log("loading Docker image")
            load_image()
            e2e_log("launching VS Code")
            launch_vscode()
            e2e_log("triggering Dev Containers reopen from command palette")
            container_id = trigger_reopen_in_container()
            e2e_log(f"waiting for container lifecycle: {container_id}")
            wait_for_container_lifecycle(container_id)
            e2e_log("waiting for VS Code GUI ready state")
            wait_for_vscode_gui_ready(container_id)
            e2e_log("probing VS Code devcontainer terminal")
            run_vscode_terminal_probe(container_id)
            e2e_log("verifying container contract")
            verify_container(container_id)
            e2e_log("collecting artifacts")
            collect_artifacts(container_id)
        except Exception:
            try:
                machine.screenshot("failure-state")
            except Exception:
                pass
            try:
                collect_artifacts(container_id)
            except Exception:
                pass
            raise
      '';
    };
in
{
  inherit
    mkVscodeGuiTest
    sessionNames
    sessionDocs
    sessions
    ;
}
