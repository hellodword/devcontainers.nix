#!/usr/bin/env python3
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def require_regex(pattern: str, text: str, label: str) -> None:
    if not re.search(pattern, text, re.MULTILINE):
        fail(f"missing pattern {pattern!r} in {label}\n{text}")


def make_unix_socket(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.bind(str(path))
        sock.listen(1)
    finally:
        sock.close()


def run_gui_refresh(gui_env: Path, home: Path, isolated_path: str, runtime_dir: Path, **extra_env: str) -> str:
    scan_dir = runtime_dir / "scan"
    scan_dir.mkdir(parents=True, exist_ok=True)
    env = {
        "HOME": str(home),
        "PATH": isolated_path,
        "XDG_RUNTIME_DIR": str(runtime_dir),
        "DEVCONTAINER_GUI_WAYLAND_SCAN_DIRS": str(scan_dir),
    }
    env.update(extra_env)
    return subprocess.run(
        [str(gui_env), "refresh"],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    ).stdout


def source_gui_env_assert(
    bash: str,
    home: Path,
    isolated_path: str,
    env_file: Path,
    script: str,
    **extra_env: str,
) -> None:
    env = {"HOME": str(home), "PATH": isolated_path}
    env.update(extra_env)
    subprocess.run(
        [bash, "-c", '. "$1"; eval "$2"', "_", str(env_file), script],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )


def main() -> int:
    gui_env_root = os.environ.get("DEVCONTAINER_GUI_ENV_TOOL")
    if not gui_env_root:
        fail("DEVCONTAINER_GUI_ENV_TOOL is required")
    gui_env = Path(gui_env_root) / "bin" / "devcontainer-gui-env"
    bash = shutil.which("bash")
    if not bash:
        fail("bash is required for gui-env check")
    isolated_path = str(Path(bash).parent)

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        home = tmpdir / "home"
        home.mkdir()
        gui_runtime = tmpdir / "gui-runtime"
        gui_runtime.mkdir()
        env_file = gui_runtime / "devcontainer-gui-env.sh"

        none_out = run_gui_refresh(gui_env, home, isolated_path, gui_runtime)
        require_regex("^backend=none$", none_out, "gui none")
        source_gui_env_assert(
            bash,
            home,
            isolated_path,
            env_file,
            'test -z "${QT_QPA_PLATFORM:-}" && test -z "${GDK_BACKEND:-}" && test -z "${NIXOS_OZONE_WL:-}"',
        )

        x11_out = run_gui_refresh(gui_env, home, isolated_path, gui_runtime, DISPLAY=":42")
        require_regex("^backend=x11$", x11_out, "gui x11")
        source_gui_env_assert(
            bash,
            home,
            isolated_path,
            env_file,
            'test "$XDG_SESSION_TYPE" = x11 && test "$GDK_BACKEND" = x11 && test "$QT_QPA_PLATFORM" = xcb && test "$SDL_VIDEODRIVER" = x11 && test "$CLUTTER_BACKEND" = x11 && test -z "${MOZ_ENABLE_WAYLAND:-}" && test -z "${NIXOS_OZONE_WL:-}" && test "$DISPLAY" = :42',
            DISPLAY=":42",
            MOZ_ENABLE_WAYLAND="1",
            NIXOS_OZONE_WL="1",
        )

        make_unix_socket(gui_runtime / "wayland-0")
        wayland_out = run_gui_refresh(
            gui_env,
            home,
            isolated_path,
            gui_runtime,
            WAYLAND_DISPLAY="wayland-0",
            DISPLAY=":42",
        )
        require_regex("^backend=wayland$", wayland_out, "gui wayland")
        source_gui_env_assert(
            bash,
            home,
            isolated_path,
            env_file,
            'test "$XDG_SESSION_TYPE" = wayland && test "$GDK_BACKEND" = wayland,x11 && test "$QT_QPA_PLATFORM" = "wayland;xcb" && test "$SDL_VIDEODRIVER" = wayland && test "$CLUTTER_BACKEND" = wayland && test "$MOZ_ENABLE_WAYLAND" = 1 && test "$NIXOS_OZONE_WL" = 1',
        )

        force_x11_out = run_gui_refresh(
            gui_env,
            home,
            isolated_path,
            gui_runtime,
            DEVCONTAINER_GUI_BACKEND="x11",
            WAYLAND_DISPLAY="wayland-0",
            DISPLAY=":42",
        )
        require_regex("^backend=x11$", force_x11_out, "gui forced x11")

        fallback_out = run_gui_refresh(
            gui_env,
            home,
            isolated_path,
            gui_runtime,
            WAYLAND_DISPLAY="missing",
            DISPLAY=":42",
        )
        require_regex("^backend=x11$", fallback_out, "gui invalid wayland fallback")

        disabled_out = run_gui_refresh(
            gui_env,
            home,
            isolated_path,
            gui_runtime,
            DEVCONTAINER_GUI_ENV="0",
            WAYLAND_DISPLAY="wayland-0",
            DISPLAY=":42",
        )
        require_regex("^enabled=0$", disabled_out, "gui disabled")
        require_regex("^backend=disabled$", disabled_out, "gui disabled")
        source_gui_env_assert(
            bash,
            home,
            isolated_path,
            env_file,
            'test -z "${QT_QPA_PLATFORM:-}" && test -z "${GDK_BACKEND:-}" && test -z "${NIXOS_OZONE_WL:-}"',
            QT_QPA_PLATFORM="xcb",
            GDK_BACKEND="x11",
            NIXOS_OZONE_WL="1",
        )

    print("gui-env-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
