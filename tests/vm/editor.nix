# Workflow 2: Fully offline VS Code Stable Dev Container session (:latest) and native Wayland window forwarding.
{
  pkgs,
  core,
  images,
}:
let
  playwrightPython = pkgs.python3.withPackages (p: [ p.playwright ]);

  editorSessionPy = pkgs.writeText "editor-session.py" ''
    """Drive offline VS Code Stable to attach to :latest Dev Container and verify integrated terminal."""

    import json
    import os
    from pathlib import Path
    import re
    import subprocess
    import sys
    import time

    from playwright.sync_api import expect, sync_playwright

    from vscode_cdp import (
        reopen_in_devcontainer,
        vscode_electron_session,
        wait_for,
    )


    def import_user_systemd_env() -> None:
        out = subprocess.run(
            ["systemctl", "--user", "show-environment"],
            check=True,
            capture_output=True,
            text=True,
            timeout=15,
        ).stdout
        for line in out.splitlines():
            if "=" not in line:
                continue
            key, val = line.split("=", 1)
            if key in {"DISPLAY", "WAYLAND_DISPLAY", "SWAYSOCK", "XDG_CURRENT_DESKTOP", "XDG_SESSION_TYPE"}:
                os.environ[key] = val
        os.environ.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")


    def wait_for_lifecycle_tasks(container_id: str, timeout: int = 180) -> dict:
        deadline = time.monotonic() + timeout
        last = {}
        last_err = ""
        while time.monotonic() < deadline:
            res = subprocess.run(
                ["docker", "exec", container_id, "devcontainer-task-runner", "status"],
                capture_output=True,
                text=True,
                check=False,
                timeout=20,
            )
            if res.returncode == 0 and res.stdout.strip():
                last = dict(
                    line.split("\t", 1)
                    for line in res.stdout.strip().splitlines()
                    if "\t" in line
                )
                if last.get("postCreate") == "done" and last.get("postStart") == "done":
                    runner_chk = subprocess.run(
                        ["docker", "exec", container_id, "pgrep", "-f", "devcontainer-task-runner"],
                        capture_output=True,
                        check=False,
                        timeout=10,
                    )
                    if runner_chk.returncode != 0:
                        time.sleep(1.5)
                        return last
            else:
                last_err = res.stderr.strip()
            time.sleep(1.0)
        raise AssertionError(
            f"Lifecycle phases did not finish cleanly within {timeout}s: {last!r} (stderr={last_err!r})"
        )


    def kill_existing_terminals(page) -> None:
        def term_count() -> int:
            return page.get_by_role("textbox", name=re.compile(r"^Terminal \d+\b")).count()

        if page.locator(".xterm-helper-textarea").count() == 0 and term_count() == 0:
            return
        page.keyboard.press("Escape")
        time.sleep(0.3)
        page.keyboard.press("F1")
        palette = page.locator(".quick-input-widget input.input")
        palette.wait_for(timeout=15000)
        palette.fill(">Terminal: Kill All Terminals")
        row = page.locator(".quick-input-list .monaco-list-row", has_text="Terminal: Kill All Terminals").first
        row.click(timeout=15000)
        for _ in range(15):
            if term_count() == 0:
                return
            kill_btn = page.get_by_role("button", name="Kill Terminal")
            if kill_btn.count() > 0 and kill_btn.first.is_visible():
                try:
                    kill_btn.first.click(timeout=2000)
                except Exception:
                    pass
            time.sleep(0.5)
        wait_for(
            lambda: term_count() == 0,
            "closing lifecycle task terminals",
            timeout=20,
        )


    def execute_in_integrated_terminal(
        page,
        command: str,
        started_file: Path,
        error_file: Path,
        report_file: Path,
        *,
        timeout: int = 120,
    ) -> str:
        for path in (started_file, error_file, report_file):
            path.unlink(missing_ok=True)
        page.keyboard.press("Control+Shift+Backquote")
        term_regex = re.compile(r"^Terminal \d+\b")
        page.get_by_role("textbox", name=term_regex).last.wait_for(timeout=60000)
        deadline = time.monotonic() + timeout
        next_send = 0.0
        while time.monotonic() < deadline:
            if report_file.exists():
                return report_file.read_text(encoding="utf-8")
            if not started_file.exists() and time.monotonic() >= next_send:
                box = page.get_by_role("textbox", name=term_regex).last
                box.focus()
                expect(box).to_be_focused(timeout=15000)
                page.keyboard.type(f"\n{command}\n", delay=15)
                next_send = time.monotonic() + 5.0
            time.sleep(0.5)
        err_txt = error_file.read_text(encoding="utf-8", errors="replace") if error_file.exists() else ""
        raise AssertionError(
            f"Timed out waiting for {report_file} (started={started_file.exists()}, err={err_txt!r})"
        )


    def main() -> int:
        workspace = Path(sys.argv[1]).resolve()
        state_dir = Path(sys.argv[2]).resolve()
        verify_script = Path(sys.argv[3]).resolve()
        artifacts_dir = state_dir / "artifacts"
        artifacts_dir.mkdir(parents=True, exist_ok=True)

        import_user_systemd_env()
        wayland_display = os.environ.get("WAYLAND_DISPLAY", "")
        wayland_sock = (
            Path(wayland_display)
            if wayland_display.startswith("/")
            else Path(os.environ["XDG_RUNTIME_DIR"]) / wayland_display
        )
        assert wayland_display and wayland_sock.is_socket(), (
            f"Host Wayland socket unavailable: WAYLAND_DISPLAY={wayland_display!r}, sock={wayland_sock}"
        )

        session_state = {}
        with sync_playwright() as playwright:
            with vscode_electron_session(
                playwright,
                [
                    "code",
                    "--wait",
                    "--new-window",
                    "--skip-welcome",
                    "--skip-release-notes",
                    "--disable-workspace-trust",
                    "--disable-telemetry",
                    "--disable-updates",
                    "--password-store=basic",
                    "--enable-features=UseOzonePlatform",
                    "--ozone-platform=wayland",
                    "--disable-gpu",
                    str(workspace),
                ],
                port=9223,
                artifacts_dir=artifacts_dir,
                name="vscode",
                state_dict=session_state,
            ) as page:
                page.locator(".monaco-workbench").wait_for(timeout=60000)
                container_id = reopen_in_devcontainer(
                    page,
                    workspace,
                    expected_host_label="Dev Container",
                    timeout=300,
                )
                tasks_state = wait_for_lifecycle_tasks(container_id, timeout=180)
                subprocess.run(
                    ["docker", "cp", str(verify_script), f"{container_id}:/tmp/verify-in-terminal.sh"],
                    check=True,
                    timeout=30,
                )
                kill_existing_terminals(page)

                started_path = workspace / ".terminal-started"
                error_path = workspace / ".terminal-error.log"
                report_path = workspace / ".terminal-report.json"
                raw_report = execute_in_integrated_terminal(
                    page,
                    "bash /tmp/verify-in-terminal.sh",
                    started_path,
                    error_path,
                    report_path,
                    timeout=120,
                )
                report = json.loads(raw_report)
                report["containerId"] = container_id
                report["lifecycleTasks"] = tasks_state

                ready_tmp = state_dir / "session-ready.json.tmp"
                ready_file = state_dir / "session-ready.json"
                ready_tmp.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
                ready_tmp.replace(ready_file)

                close_signal = state_dir / "close-vscode"
                wait_for(
                    lambda: close_signal.exists(),
                    "host Wayland foot window & screenshot completion",
                    timeout=240,
                )
        return 0


    if __name__ == "__main__":
        raise SystemExit(main())
  '';

  terminalVerifySh = pkgs.writeText "verify-in-terminal.sh" ''
    set -euo pipefail
    touch /workspaces/workspace/.terminal-started
    exec 2>/workspaces/workspace/.terminal-error.log

    user_name="$(id -un)"
    uid_num="$(id -u)"
    gid_num="$(id -g)"
    cwd_path="$PWD"

    test "$user_name" = "vscode"
    test "$uid_num" = "1000"
    test "$gid_num" = "1000"
    test "$cwd_path" = "/workspaces/workspace"

    # .devcontainer must be mounted read-only.
    if touch /workspaces/workspace/.devcontainer/ro-write-probe 2>/dev/null; then
      echo ".devcontainer mount is unexpectedly writable" >&2
      exit 1
    fi

    # Outbound network must be completely unreachable.
    if curl -sS --connect-timeout 2 http://1.1.1.1 >/dev/null 2>&1; then
      echo "External IP unexpectedly reachable" >&2
      exit 1
    fi
    if curl -sS --connect-timeout 2 https://marketplace.visualstudio.com >/dev/null 2>&1; then
      echo "External DNS/HTTPS unexpectedly reachable" >&2
      exit 1
    fi

    # Machine settings.json must be mode 0444 read-only and match expected keys.
    settings_file="/home/vscode/.vscode-server/data/Machine/settings.json"
    test -f "$settings_file"
    test "$(stat -c '%a' "$settings_file")" = "444"
    if touch "$settings_file" 2>/dev/null; then
      echo "Machine/settings.json is unexpectedly writable" >&2
      exit 1
    fi
    jq -e '."rust-analyzer.server.path" == "/usr/bin/rust-analyzer" and ."nix.serverPath" == "/usr/bin/nixd"' "$settings_file" >/dev/null

    # All 26 offline extensions must be projected into VS Code server extension roots.
    ext_count="$(python3 -c '
    import json, pathlib, sys
    expected = json.loads(sys.argv[1])
    assert len(expected) == 26, len(expected)
    for root in (
        "/home/vscode/.vscode-server/extensions",
        "/home/vscode/.vscode-server-insiders/extensions",
        "/home/vscode/.vscode-remote/extensions",
    ):
        target = pathlib.Path(root)
        for store_dir in expected:
            src = pathlib.Path(store_dir)
            dest = target / src.name
            assert dest.is_symlink(), f"Missing projected symlink: {dest}"
            assert dest.resolve() == src.resolve(), f"Unexpected target for {dest}"
            assert (dest / "package.json").is_file(), f"Missing package.json in {dest}"
    print(len(expected))
    ' ${pkgs.lib.escapeShellArg (builtins.toJSON images.editor.extensionStorePaths)})"
    test "$ext_count" = "26"

    # Representative built-in language tools.
    ra_ver="$(rust-analyzer --version)"
    rustc_ver="$(rustc --version)"
    printf '%s\n' "$rustc_ver" | grep -Fiq nightly
    ruff check /workspaces/workspace/app.py >/dev/null
    nixfmt --check /workspaces/workspace/sample.nix
    go_ver="$(go version)"
    tsc_ver="$(tsc --version)"

    # Native Wayland forwarding status and host Sway protocol inspection.
    gui_status="$(devcontainer-gui-env status)"
    printf '%s\n' "$gui_status" | grep -Fq "backend=wayland"
    printf '%s\n' "$gui_status" | grep -Fq "wayland_socket_valid=1"

    wl_info="$(wayland-info)"
    printf '%s\n' "$wl_info" | grep -Fq "wl_compositor"
    printf '%s\n' "$wl_info" | grep -Fq "xdg_wm_base"

    python3 - \
      "$user_name" "$uid_num" "$gid_num" "$cwd_path" "$ext_count" \
      "$ra_ver" "$rustc_ver" "$go_ver" "$tsc_ver" "$gui_status" <<'PY' > /workspaces/workspace/.terminal-report.json.tmp
    import json, sys
    (
        user_name,
        uid_num,
        gid_num,
        cwd_path,
        ext_count,
        ra_ver,
        rustc_ver,
        go_ver,
        tsc_ver,
        gui_status,
    ) = sys.argv[1:]
    print(json.dumps({
        "status": "ok",
        "user": user_name,
        "uid": int(uid_num),
        "gid": int(gid_num),
        "cwd": cwd_path,
        "projectedExtensions": int(ext_count),
        "rustAnalyzer": ra_ver,
        "rustc": rustc_ver,
        "go": go_ver,
        "tsc": tsc_ver,
        "guiStatus": dict(line.split("=", 1) for line in gui_status.splitlines() if "=" in line),
    }, indent=2))
    PY
    mv -f /workspaces/workspace/.terminal-report.json.tmp /workspaces/workspace/.terminal-report.json
  '';

  mountStoreClosurePy = pkgs.writeText "mount-store-closure-ro.py" ''
    """Read-only bind-mount a host /nix/store closure into a running container mount namespace."""

    import ctypes
    import os
    from pathlib import Path
    import subprocess
    import sys

    SYS_OPEN_TREE = 428
    SYS_MOVE_MOUNT = 429
    SYS_MOUNT_SETATTR = 442
    AT_FDCWD = -100
    AT_EMPTY_PATH = 0x1000
    AT_SYMLINK_NOFOLLOW = 0x100
    OPEN_TREE_CLONE = 1
    OPEN_TREE_CLOEXEC = 0o2000000
    MOVE_MOUNT_F_EMPTY_PATH = 0x00000004
    MOUNT_ATTR_RDONLY = 0x00000001
    CLONE_NEWNS = 0x00020000


    class MountAttr(ctypes.Structure):
        _fields_ = [
            ("attr_set", ctypes.c_uint64),
            ("attr_clr", ctypes.c_uint64),
            ("propagation", ctypes.c_uint64),
            ("userns_fd", ctypes.c_uint64),
        ]


    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    libc.syscall.restype = ctypes.c_long


    def check_syscall(ret: int, desc: str) -> int:
        if ret < 0:
            err = ctypes.get_errno()
            raise OSError(err, f"{desc}: {os.strerror(err)}")
        return ret


    def main() -> int:
        container_id = sys.argv[1]
        root_store_path = sys.argv[2]

        pid = int(
            subprocess.check_output(
                ["docker", "inspect", "-f", "{{.State.Pid}}", container_id],
                text=True,
            ).strip()
        )
        closure = subprocess.check_output(
            ["nix-store", "-qR", root_store_path],
            text=True,
        ).splitlines()

        existing = set(
            subprocess.check_output(
                [
                    "docker",
                    "exec",
                    container_id,
                    "python3",
                    "-c",
                    "import json, os, sys; paths = json.loads(sys.argv[1]); print('\\n'.join(p for p in paths if os.path.lexists(p)))",
                    json.dumps(closure) if "json" in globals() else __import__("json").dumps(closure),
                ],
                text=True,
            ).splitlines()
        )
        missing = [p for p in closure if p and p not in existing]
        if not missing:
            return 0

        # Prepare empty mountpoints inside container /nix/store owned by vscode.
        prep_payload = __import__("json").dumps(
            [{"path": p, "isDir": Path(p).is_dir()} for p in missing]
        )
        subprocess.run(
            [
                "docker",
                "exec",
                container_id,
                "python3",
                "-c",
                (
                    "import json, pathlib, sys; "
                    "items = json.loads(sys.argv[1]); "
                    "[pathlib.Path(i['path']).mkdir(parents=True, exist_ok=True) if i['isDir'] else pathlib.Path(i['path']).touch() for i in items]"
                ),
                prep_payload,
            ],
            check=True,
        )

        tree_fds: list[tuple[str, int]] = []
        for path in missing:
            raw = os.fsencode(path)
            tfd = check_syscall(
                libc.syscall(
                    ctypes.c_long(SYS_OPEN_TREE),
                    ctypes.c_int(AT_FDCWD),
                    ctypes.c_char_p(raw),
                    ctypes.c_uint(OPEN_TREE_CLONE | OPEN_TREE_CLOEXEC | AT_SYMLINK_NOFOLLOW),
                ),
                f"open_tree({path})",
            )
            attr = MountAttr(attr_set=MOUNT_ATTR_RDONLY, attr_clr=0, propagation=0, userns_fd=0)
            check_syscall(
                libc.syscall(
                    ctypes.c_long(SYS_MOUNT_SETATTR),
                    ctypes.c_int(tfd),
                    ctypes.c_char_p(b""),
                    ctypes.c_uint(AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW),
                    ctypes.byref(attr),
                    ctypes.c_size_t(ctypes.sizeof(attr)),
                ),
                f"mount_setattr(RDONLY, {path})",
            )
            tree_fds.append((path, tfd))

        mnt_ns_fd = os.open(f"/proc/{pid}/ns/mnt", os.O_RDONLY)
        child = os.fork()
        if child == 0:
            try:
                os.setns(mnt_ns_fd, CLONE_NEWNS)
                for path, tfd in tree_fds:
                    raw = os.fsencode(path)
                    check_syscall(
                        libc.syscall(
                            ctypes.c_long(SYS_MOVE_MOUNT),
                            ctypes.c_int(tfd),
                            ctypes.c_char_p(b""),
                            ctypes.c_int(AT_FDCWD),
                            ctypes.c_char_p(raw),
                            ctypes.c_uint(MOVE_MOUNT_F_EMPTY_PATH),
                        ),
                        f"move_mount({path})",
                    )
                os._exit(0)
            except Exception as exc:
                print(f"mount-store-closure-ro child error: {exc}", file=sys.stderr, flush=True)
                os._exit(1)

        _, status = os.waitpid(child, 0)
        os.close(mnt_ns_fd)
        for _, tfd in tree_fds:
            os.close(tfd)
        if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
            raise SystemExit(f"Child mount process failed with status {status}")
        return 0


    if __name__ == "__main__":
        raise SystemExit(main())
  '';
in
core.lib.testing.mkTest pkgs (
  { ... }:
  {
    name = "devcontainers-editor-wayland-workflow";
    globalTimeout = 2400;
    qemu.forceAccel = true;
    node.pkgsReadOnly = false;

    nodes.machine =
      { pkgs, ... }:
      {
        imports = [
          (core.lib.testing.mkContainerHostModule {
            user = "desktop";
            uid = 1000;
            gid = 1000;
          })
          (core.lib.testing.mkSwayEditorModule {
            user = "desktop";
            uid = 1000;
            gid = 1000;
          })
        ];

        users.users.desktop.group = "desktop";

        virtualisation = {
          cores = 4;
          memorySize = 8192;
          diskSize = 16384;
          emptyDiskImages = [
            {
              size = 32768;
              driveConfig.driveExtraOpts.cache = "unsafe";
            }
          ];
          fileSystems."/var/lib/docker" = {
            device = "/dev/vdb";
            fsType = "ext4";
            autoFormat = true;
            options = [ "noatime" ];
          };
        };

        networking.firewall.enable = false;

        environment.systemPackages = [
          pkgs.curl
          pkgs.findutils
          pkgs.foot
          pkgs.gnutar
          pkgs.gzip
          pkgs.iproute2
          pkgs.jq
          pkgs.netpbm
          pkgs.python3
          pkgs.skopeo
          pkgs.util-linux
          pkgs.wayland-utils
        ];
      };

    testScript = ''
      import json
      from pathlib import Path
      import runpy
      import shlex
      import struct
      import time

      gui = runpy.run_path("${core.lib.testing.guiPy}")
      runtime = runpy.run_path("${core.lib.testing.runtimePy}")
      Desktop = gui["Desktop"]
      desktop = Desktop(machine, user="desktop", uid=1000)

      OCI_DIR = ${builtins.toJSON "${images.oci}"}
      FOOT_PKG = ${builtins.toJSON "${pkgs.foot}"}
      PLAYWRIGHT_PYTHON = ${builtins.toJSON "${playwrightPython}/bin/python3"}
      TESTING_DIR = ${builtins.toJSON "${core.lib.testing.testingDir}"}
      EDITOR_SESSION_PY = ${builtins.toJSON "${editorSessionPy}"}
      TERMINAL_VERIFY_SH = ${builtins.toJSON "${terminalVerifySh}"}
      MOUNT_CLOSURE_PY = ${builtins.toJSON "${mountStoreClosurePy}"}
      LATEST_REF = "ghcr.io/hellodword/devcontainers-dev:latest"

      def q(val: str) -> str:
          return shlex.quote(str(val))

      def as_desktop(cmd: str) -> str:
          return "su - desktop -c " + q(cmd)

      captures = [
          (machine, "docker", "journalctl -u docker --no-pager -n 200"),
          (machine, "greetd", "journalctl -u greetd --no-pager -n 120"),
          (machine, "user-journal", "journalctl _UID=1000 --no-pager -n 200"),
          (machine, "session-log", "cat /home/desktop/editor-state/session.log || true"),
          (machine, "vscode-log", "cat /home/desktop/editor-state/artifacts/vscode.log || true"),
          (machine, "vscode-aria", "cat /home/desktop/editor-state/artifacts/vscode-accessibility.txt || true"),
          (
              machine,
              "remotecontainers-log",
              "grep -R -H -n . /home/desktop/.config/Code/logs/*/window*/exthost/ms-vscode-remote.remote-containers/ 2>/dev/null | tail -n 250 || true",
          ),
      ]

      with runtime["scenario"]([machine], captures, [desktop]):
          start_all()
          machine.succeed("findmnt -n /var/lib/docker | grep -F /dev/vdb")
          machine.wait_for_unit("docker.service")
          machine.wait_until_succeeds(as_desktop("docker info >/dev/null"), timeout=60)
          gui["wait_for_session"](
              machine,
              "sway",
              desktop.session_command,
              target_unit="sway-ready.target",
              require_fcitx=False,
          )
          desktop.inhibit_idle()

          with subtest("1. Load :latest directly from store OCI layout and sever all outbound network"):
              machine.succeed(
                  as_desktop(
                      f"tmpdir=$(mktemp -d) && trap 'rm -rf \"$tmpdir\"' EXIT && "
                      f"skopeo --tmpdir \"$tmpdir\" --insecure-policy copy oci:{q(OCI_DIR)}:latest docker-daemon:{LATEST_REF}"
                  ),
                  timeout=600,
              )

              machine.succeed(
                  "systemctl stop dhcpcd.service || true && "
                  "ip route del default || true && "
                  "ip -6 route del default || true && "
                  "ip addr flush dev eth0 || true && "
                  "ip link set eth0 down"
              )
              # Verify host outbound IP/DNS are completely unreachable while loopback works.
              machine.succeed(
                  "! curl -sS --connect-timeout 2 http://1.1.1.1 >/dev/null 2>&1 && "
                  "! curl -sS --connect-timeout 2 https://cache.nixos.org >/dev/null 2>&1 && "
                  "ip addr show dev lo | grep -Fq '127.0.0.1'"
              )

          with subtest("2. Prepare minimal workspace with image-only devcontainer.json"):
              prep_workspace = """
      set -euo pipefail
      rm -rf /home/desktop/workspace /home/desktop/editor-state
      mkdir -p /home/desktop/workspace/.devcontainer /home/desktop/editor-state /home/desktop/.config/Code/User
      cat <<'EOF' > /home/desktop/.config/Code/User/settings.json
      {
        "remote.serverDownloadBaseUrl": "http://127.0.0.1:9/offline-cache-only",
        "remote.serverDownloadFolder": "/home/desktop/.cache/vscode-server-downloads",
        "dev.containers.cacheVolume": false,
        "dev.containers.mountWaylandSocket": true,
        "dev.containers.copyGitConfig": false,
        "dev.containers.defaultExtensions": [],
        "dev.containers.dockerCredentialHelper": false,
        "dev.containers.dockerPath": "docker",
        "dev.containers.dockerSocketPath": "/var/run/docker.sock",
        "dev.containers.gpuAvailability": "none",
        "dev.containers.logLevel": "trace",
        "remote.autoForwardPorts": false,
        "security.workspace.trust.emptyWindow": false,
        "security.workspace.trust.enabled": false,
        "security.workspace.trust.startupPrompt": "never",
        "workbench.startupEditor": "none",
        "workbench.welcomePage.walkthroughs.openOnInstall": false,
        "extensions.autoCheckUpdates": false,
        "extensions.autoUpdate": false,
        "extensions.ignoreRecommendations": true,
        "update.mode": "none",
        "telemetry.enableTelemetry": false,
        "telemetry.telemetryLevel": "off",
        "chat.disableAIFeatures": true,
        "chat.commandCenter.enabled": false,
        "chat.agent.enabled": false,
        "chat.detectParticipant.enabled": false,
        "chat.titleBar.signIn.enabled": false,
        "window.restoreWindows": "none",
        "window.titleBarStyle": "custom"
      }
      EOF
      chmod 0644 /home/desktop/.config/Code/User/settings.json
      compgen -G '/home/desktop/.cache/vscode-server-downloads/*/vscode-server-linux-*.tar.gz' >/dev/null
      cat <<'EOF' > /home/desktop/workspace/.devcontainer/devcontainer.json
      {
        "image": "ghcr.io/hellodword/devcontainers-dev:latest"
      }
      EOF
      cat <<'EOF' > /home/desktop/workspace/main.rs
      fn main() {
          println!("offline-rust");
      }
      EOF
      cat <<'EOF' > /home/desktop/workspace/app.py
      def add(left: int, right: int) -> int:
          return left + right


      if __name__ == "__main__":
          print(add(20, 22))
      EOF
      cat <<'EOF' > /home/desktop/workspace/sample.nix
      x: x + 1
      EOF
      cat <<'EOF' > /home/desktop/workspace/main.go
      package main

      import "fmt"

      func main() {
      	fmt.Println("offline-go")
      }
      EOF
      cat <<'EOF' > /home/desktop/workspace/index.ts
      export const answer: number = 42;
      EOF
      chown -R desktop:desktop /home/desktop/workspace /home/desktop/editor-state /home/desktop/.config /home/desktop/.cache
      """
              machine.succeed(prep_workspace)
              cfg_json = json.loads(
                  machine.succeed("cat /home/desktop/workspace/.devcontainer/devcontainer.json")
              )
              assert cfg_json == {"image": LATEST_REF}, f"Unexpected devcontainer.json: {cfg_json!r}"

          with subtest("3. Attach offline VS Code Stable in Sway, verify 26 extensions, RO mounts, and tools"):
              launch_cmd = (
                  f"PYTHONPATH={q(TESTING_DIR)} "
                  f"{q(PLAYWRIGHT_PYTHON)} {q(EDITOR_SESSION_PY)} "
                  f"/home/desktop/workspace /home/desktop/editor-state {q(TERMINAL_VERIFY_SH)} "
                  ">/home/desktop/editor-state/session.log 2>&1"
              )
              machine.succeed(
                  "runuser -u desktop -- env XDG_RUNTIME_DIR=/run/user/1000 "
                  "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus "
                  f"systemd-run --user --unit=vscode-editor-e2e sh -c {q(launch_cmd)}"
              )

              deadline = time.monotonic() + 360
              while time.monotonic() < deadline:
                  _, state_u = machine.execute(
                      "runuser -u desktop -- env XDG_RUNTIME_DIR=/run/user/1000 "
                      "systemctl --user show -p ActiveState -p Result vscode-editor-e2e.service"
                  )
                  if "Result=exit-code" in state_u or "ActiveState=failed" in state_u:
                      log_text = machine.succeed("cat /home/desktop/editor-state/session.log || true")
                      raise AssertionError(f"vscode-editor-e2e failed early:\n{state_u}\n{log_text}")

                  rc_ready, _ = machine.execute("test -f /home/desktop/editor-state/session-ready.json")
                  if rc_ready == 0:
                      break
                  time.sleep(1.0)
              else:
                  log_text = machine.succeed("cat /home/desktop/editor-state/session.log || true")
                  raise AssertionError(f"Timed out waiting for VS Code integrated terminal report:\n{log_text}")

              report = json.loads(machine.succeed("cat /home/desktop/editor-state/session-ready.json"))
              assert report["status"] == "ok", report
              assert report["user"] == "vscode" and report["uid"] == 1000, report
              assert report["cwd"] == "/workspaces/workspace", report
              assert report["projectedExtensions"] == 26, report
              assert report["guiStatus"].get("backend") == "wayland", report
              assert report["guiStatus"].get("wayland_socket_valid") == "1", report
              cid = report["containerId"]

              # Save terminal verification report to $out/
              (Path(machine.out_dir) / "editor-terminal-report.json").write_text(
                  json.dumps(report, indent=2) + "\n", encoding="utf-8"
              )

          with subtest("4. Bind-mount pkgs.foot closure read-only into container, verify Sway Wayland window, and capture 1920x1080 screenshot"):
              machine.succeed(f"python3 {q(MOUNT_CLOSURE_PY)} {q(cid)} {q(FOOT_PKG)}", timeout=120)

              # Confirm pkgs.foot inside container is genuinely mounted read-only.
              machine.succeed(
                  as_desktop(
                      f"docker exec {q(cid)} bash -euo pipefail -c "
                      + q(
                          f"test -x {q(FOOT_PKG)}/bin/foot && "
                          f"if touch {q(FOOT_PKG)}/ro-probe 2>/dev/null; then exit 1; fi"
                      )
                  )
              )

              # Launch native Wayland foot client inside the running Dev Container.
              foot_inner = (
                  ". /run/user/1000/devcontainer-gui-env.sh && "
                  f"exec {q(FOOT_PKG)}/bin/foot sh -c "
                  + q(
                      "printf '=== Native Wayland foot inside :latest Dev Container ===\\n'; "
                      "id; pwd; devcontainer-gui-env status; echo; wayland-info | head -n 16; sleep 300"
                  )
              )
              machine.succeed(
                  as_desktop(f"docker exec -d {q(cid)} bash -lc {q(foot_inner)}")
              )

              # Assert on host Sway compositor tree that app_id == "foot" is created, visible, and focused.
              sway_query = (
                  "swaymsg -t get_tree | jq -e '"
                  "[.. | objects | select(.app_id? == \"foot\" and .visible? == true and .focused? == true)] | length >= 1"
                  "'"
              )
              machine.wait_until_succeeds(desktop.session_command(sway_query), timeout=60)
              time.sleep(1.5)

              sway_tree = machine.succeed(desktop.session_command("swaymsg -t get_tree"))
              (Path(machine.out_dir) / "sway-tree.json").write_text(sway_tree, encoding="utf-8")

              screenshot_path = Path(machine.out_dir) / "sway-vscode-wayland-foot.png"
              desktop.screenshot(str(screenshot_path))
              assert screenshot_path.is_file(), "Expected QMP screenshot file to exist"
              png_header = screenshot_path.read_bytes()[:24]
              assert png_header[:8] == b"\x89PNG\r\n\x1a\n", "Invalid PNG signature"
              width, height = struct.unpack(">II", png_header[16:24])
              assert (width, height) == (1920, 1080), f"Expected 1920x1080 screenshot, got {width}x{height}"

              # Signal VS Code session helper to close cleanly and wait for unit completion.
              machine.succeed("touch /home/desktop/editor-state/close-vscode && chown desktop:desktop /home/desktop/editor-state/close-vscode")
              machine.wait_until_succeeds(
                  "runuser -u desktop -- env XDG_RUNTIME_DIR=/run/user/1000 "
                  "systemctl --user show -p ActiveState vscode-editor-e2e.service | grep -Fq 'ActiveState=inactive'",
                  timeout=60,
              )
              machine.succeed(as_desktop(f"docker rm -f {q(cid)} >/dev/null 2>&1 || true"))
    '';
  }
)
