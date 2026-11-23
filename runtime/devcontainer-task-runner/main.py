#!/usr/bin/env python3
"""Lifecycle helper for :latest Dev Containers (postCreate extension symlinks and postStart refresh)."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, "@runtimeLibrary@")
import devcontainer_state as state

PROJECTION_TARGETS: list[str] = json.loads(r"""@projectionTargetsJson@""")
EXTENSION_STORE_PATHS: list[str] = json.loads(r"""@extensionStorePathsJson@""")
GUI_ENV_BIN = "@guiEnv@"

USAGE = """devcontainer-task-runner run <postCreate|postStart>
devcontainer-task-runner status
"""


def tasks_state_dir() -> Path:
    home = os.environ.get("HOME") or "/home/vscode"
    state_home = Path(
        os.environ.get("XDG_STATE_HOME") or (Path(home) / ".local" / "state")
    )
    return state_home / "devcontainer" / "tasks"


def write_status(phase: str, value: str) -> None:
    target = tasks_state_dir() / f"{phase}.status"
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=target.parent, prefix=f".{phase}-", delete=False
    ) as handle:
        tmp = Path(handle.name)
        try:
            handle.write(f"{value}\n")
            handle.flush()
            os.replace(tmp, target)
        finally:
            tmp.unlink(missing_ok=True)


def read_status(phase: str) -> str:
    path = tasks_state_dir() / f"{phase}.status"
    try:
        return path.read_text(encoding="utf-8").strip() or "pending"
    except FileNotFoundError:
        return "pending"


def projections_intact() -> bool:
    for target_str in PROJECTION_TARGETS:
        target = Path(target_str)
        for src_str in EXTENSION_STORE_PATHS:
            dest = target / Path(src_str).name
            if not dest.is_symlink() or os.readlink(dest) != src_str:
                return False
    return True


def project_extensions() -> None:
    sources = [Path(p) for p in EXTENSION_STORE_PATHS]
    for src in sources:
        if not src.exists():
            raise RuntimeError(f"missing extension store path: {src}")
    for target_str in PROJECTION_TARGETS:
        target = Path(target_str)
        target.mkdir(parents=True, exist_ok=True)
        for src in sources:
            dest = target / src.name
            if dest.is_symlink() and os.readlink(dest) == str(src):
                continue
            if dest.is_symlink() or dest.is_file():
                dest.unlink()
            elif dest.is_dir():
                shutil.rmtree(dest)
            os.symlink(src, dest)


def run_post_create() -> int:
    state.ensure_xdg(os.environ)
    if read_status("postCreate") == "done" and projections_intact():
        return 0
    project_extensions()
    write_status("postCreate", "done")
    return 0


def run_post_start() -> int:
    subprocess.run([GUI_ENV_BIN, "refresh"], check=True)
    state.refresh_local_cache(os.environ)
    write_status("postStart", "done")
    return 0


def main(argv: list[str]) -> int:
    if argv == ["status"]:
        for phase in ("postCreate", "postStart"):
            print(f"{phase}\t{read_status(phase)}")
        return 0
    if len(argv) == 2 and argv[0] == "run" and argv[1] in {"postCreate", "postStart"}:
        phase = argv[1]
        try:
            return run_post_create() if phase == "postCreate" else run_post_start()
        except (
            state.StateError,
            RuntimeError,
            OSError,
            subprocess.CalledProcessError,
        ) as exc:
            write_status(phase, "failed")
            print(f"devcontainer-task-runner: {exc}", file=sys.stderr)
            return 1
    print(USAGE, end="", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
