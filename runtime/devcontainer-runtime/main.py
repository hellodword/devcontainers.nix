#!/usr/bin/env python3
"""Trusted startup: optional identity setup, privilege drop, state, then exec."""

import json
import os
import pwd
import sys
from pathlib import Path

sys.path.insert(0, "@runtimeLibrary@")
import devcontainer_identity as identity
import devcontainer_state as state


def main(argv: list[str]) -> int:
    try:
        requested_id = state.requested_machine_id(os.environ)
        account = pwd.getpwnam("vscode")
        uid_value = os.environ.get("DEVCONTAINER_UID")
        gid_value = os.environ.get("DEVCONTAINER_GID")
        uid = identity.parse_numeric_id("DEVCONTAINER_UID", uid_value) if uid_value is not None else account.pw_uid
        gid = identity.parse_numeric_id("DEVCONTAINER_GID", gid_value) if gid_value is not None else account.pw_gid
    except (identity.UsageError, state.StateError) as exc:
        print(f"devcontainer-entrypoint: {exc}", file=sys.stderr)
        return 2
    except KeyError:
        print("devcontainer-entrypoint: vscode account is missing", file=sys.stderr)
        return 126

    try:
        mounts = identity.mount_points()
        root = Path("/")
        state.validate_machine_id(root, requested_id, mounts)
        if os.geteuid() == 0:
            if uid_value is None and gid_value is None:
                print("devcontainer-entrypoint: run as vscode; root startup requires DEVCONTAINER_UID or DEVCONTAINER_GID", file=sys.stderr)
                return 126
            identity.set_user_id(root, uid, gid)
            os.setgroups([])
            os.setgid(gid)
            os.setuid(uid)
            os.environ.update(HOME=account.pw_dir, USER="vscode", LOGNAME="vscode")
        elif os.geteuid() != account.pw_uid or os.getegid() != account.pw_gid:
            print("devcontainer-entrypoint: images must run as the vscode user and group", file=sys.stderr)
            return 126
        elif uid != account.pw_uid or gid != account.pw_gid:
            print("devcontainer-entrypoint: changing DEVCONTAINER_UID/GID requires docker run --user 0", file=sys.stderr)
            return 126

        defaults = json.loads(Path("/usr/share/devcontainer/runtime.json").read_text())
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
        if not runtime_dir or runtime_dir in {defaults["runtimeDir"], f"/run/user/{account.pw_uid}"}:
            runtime_dir = f"/run/user/{os.geteuid()}"
        os.environ["XDG_RUNTIME_DIR"] = runtime_dir
        state.ensure_xdg(os.environ, runtime_dir)
        state.ensure_machine_id(root, requested_id, mounts)
        # Both the GUI refresh and the user's command execute after the drop.
        command = ["@bash@", "@session@", *(argv or ["sleep", "infinity"])]
        if os.getpid() == 1:
            command = ["@tini@", "-g", "--", *command]
        os.execv(command[0], command)
    except (identity.ApplyError, state.StateError, OSError, ValueError) as exc:
        print(f"devcontainer-entrypoint: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
