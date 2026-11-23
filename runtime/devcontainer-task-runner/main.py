#!/usr/bin/env python3
"""Lifecycle helper for :latest Dev Containers (postCreate extension symlinks and postStart refresh)."""

import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, "@runtimeLibrary@")
import devcontainer_state as state

DEFAULT_HOME = Path("/home/vscode")
PROJECTION_TARGETS: list[str] = json.loads(r"""@projectionTargetsJson@""")
EXTENSION_STORE_PATHS: list[str] = json.loads(r"""@extensionStorePathsJson@""")
GUI_ENV_BIN = "@guiEnv@"

USAGE = """devcontainer-task-runner run <postCreate|postStart>
devcontainer-task-runner status
"""


def home_dir() -> Path:
    return Path(os.environ.get("HOME") or str(DEFAULT_HOME))


def projection_targets() -> list[Path]:
    home = home_dir()
    targets: list[Path] = []
    for raw in PROJECTION_TARGETS:
        path = Path(raw)
        if home != DEFAULT_HOME and path.is_relative_to(DEFAULT_HOME):
            targets.append(home / path.relative_to(DEFAULT_HOME))
        else:
            targets.append(path)
    return targets


def tasks_state_dir() -> Path:
    home = home_dir()
    state_home = Path(os.environ.get("XDG_STATE_HOME") or (home / ".local" / "state"))
    return state_home / "devcontainer" / "tasks"


@contextmanager
def phase_lock(phase: str):
    lock_dir = tasks_state_dir()
    lock_dir.mkdir(parents=True, exist_ok=True)
    lock_path = lock_dir / f".{phase}.lock"
    fd = os.open(
        lock_path,
        os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
    )
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


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
    for target in projection_targets():
        for src_str in EXTENSION_STORE_PATHS:
            dest = target / Path(src_str).name
            try:
                if not dest.is_symlink() or os.readlink(dest) != src_str:
                    return False
            except OSError:
                return False
    return True


def replace_with_symlink(src: Path, dest: Path) -> None:
    try:
        if dest.is_symlink() and os.readlink(dest) == str(src):
            return
    except OSError:
        pass
    if not dest.is_symlink() and dest.is_dir():
        shutil.rmtree(dest)
    tmp_dir = Path(tempfile.mkdtemp(dir=dest.parent, prefix=f".{dest.name}."))
    tmp_link = tmp_dir / "link"
    try:
        os.symlink(src, tmp_link)
        os.replace(tmp_link, dest)
    finally:
        tmp_link.unlink(missing_ok=True)
        try:
            tmp_dir.rmdir()
        except OSError:
            pass


def project_extensions() -> None:
    sources = [Path(p) for p in EXTENSION_STORE_PATHS]
    for src in sources:
        if not src.exists():
            raise RuntimeError(f"missing extension store path: {src}")
    for target in projection_targets():
        target.mkdir(parents=True, exist_ok=True)
        for src in sources:
            replace_with_symlink(src, target / src.name)


def run_post_create() -> int:
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
            state.ensure_xdg(os.environ)
        except (state.StateError, OSError) as exc:
            print(f"devcontainer-task-runner: {exc}", file=sys.stderr)
            return 1
        with phase_lock(phase):
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
