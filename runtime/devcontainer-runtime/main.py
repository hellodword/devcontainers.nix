#!/usr/bin/env python3
"""Container entrypoint: verify vscode identity, initialize runtime state, probe host cache, and exec."""

import os
import pwd
import shlex
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "@runtimeLibrary@")
import devcontainer_state as state

POST_BUILD_HOOK = "@nixPostBuildHook@"


def apply_gui_env_fragment(env_file: Path) -> None:
    if not env_file.is_file():
        return
    try:
        lines = env_file.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export ") and "=" in line:
            assignment = line[len("export ") :]
            key, rhs = assignment.split("=", 1)
            parts = shlex.split(rhs)
            os.environ[key] = parts[0] if parts else ""
        elif line.startswith("unset "):
            key = line[len("unset ") :].strip()
            os.environ.pop(key, None)


def refresh_gui_env(runtime_dir: str) -> None:
    gui_tool = Path("@guiEnv@")
    if not gui_tool.is_file():
        return
    subprocess.run(
        [str(gui_tool), "refresh"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    env_file = Path(
        os.environ.get("DEVCONTAINER_GUI_ENV_FILE")
        or f"{runtime_dir}/devcontainer-gui-env.sh"
    )
    apply_gui_env_fragment(env_file)


def main(argv: list[str]) -> int:
    if Path(sys.argv[0]).name == "devcontainer-runtime":
        if argv == ["refresh-local-cache"]:
            try:
                state.refresh_local_cache(os.environ, post_build_hook=POST_BUILD_HOOK)
            except (state.StateError, OSError) as exc:
                print(f"devcontainer-runtime: {exc}", file=sys.stderr)
                return 1
            return 0
        if argv and argv[0] == "prune-caches":
            import devcontainer_cache_gc as cache_gc

            try:
                return cache_gc.run_cli(argv[1:], os.environ)
            except (state.StateError, OSError, TypeError, ValueError) as exc:
                print(f"devcontainer-runtime: {exc}", file=sys.stderr)
                return 1

    try:
        account = pwd.getpwnam("vscode")
    except KeyError:
        print("devcontainer-entrypoint: vscode account is missing", file=sys.stderr)
        return 126

    euid = os.geteuid()
    egid = os.getegid()
    if euid == 0 or euid != account.pw_uid or egid != account.pw_gid:
        print(
            f"devcontainer-entrypoint: container must run as vscode ({account.pw_uid}:{account.pw_gid}), "
            f"got {euid}:{egid}; derive non-default IDs at build time with devcontainer-set-user-id",
            file=sys.stderr,
        )
        return 126

    try:
        mounts = state.mount_points()
        root = Path("/")
        state.validate_machine_id(root, mounts)

        os.environ["HOME"] = account.pw_dir
        os.environ["USER"] = "vscode"
        os.environ["LOGNAME"] = "vscode"
        expected_runtime_dir = f"/run/user/{account.pw_uid}"
        current_runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "")
        if not current_runtime_dir or current_runtime_dir.startswith("/run/user/"):
            runtime_dir = expected_runtime_dir
        else:
            runtime_dir = current_runtime_dir
        os.environ["XDG_RUNTIME_DIR"] = runtime_dir

        state.ensure_xdg(os.environ, runtime_dir)
        state.ensure_machine_id(root, mounts)
        state.refresh_local_cache(
            os.environ, mounts=mounts, post_build_hook=POST_BUILD_HOOK
        )
        refresh_gui_env(runtime_dir)

        target = argv if argv else ["@bash@"]
        if os.getpid() == 1:
            command = ["@tini@", "-g", "--", *target]
        else:
            command = list(target)
        os.execvp(command[0], command)
    except state.StateError as exc:
        print(f"devcontainer-entrypoint: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"devcontainer-entrypoint: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
