#!/usr/bin/env python3
import importlib.util
import os
import subprocess
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_helper(helper: Path):
    loader = SourceFileLoader("devcontainer_set_user_id", str(helper))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    if spec is None or spec.loader is None:
        fail(f"failed to import helper: {helper}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run_helper(helper: Path, args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [str(helper), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def write_identity(root: Path, *, extra_passwd: str = "", extra_group: str = "") -> None:
    etc = root / "etc"
    etc.mkdir(parents=True)
    (etc / "passwd").write_text(
        "root:x:0:0:root:/root:/bin/bash\n"
        "vscode:x:1000:1000:vscode:/home/vscode:/bin/bash\n"
        f"{extra_passwd}",
        encoding="utf-8",
    )
    (etc / "group").write_text(
        "root:x:0:\n"
        "vscode:x:1000:vscode\n"
        f"{extra_group}",
        encoding="utf-8",
    )


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> int:
    helper_root = os.environ.get("DEVCONTAINER_SET_USER_ID")
    if not helper_root:
        fail("DEVCONTAINER_SET_USER_ID is required")
    helper = Path(helper_root) / "bin" / "devcontainer-set-user-id"
    module = load_helper(helper)

    invalid = run_helper(helper, ["--uid", "abc", "--gid", "100"])
    if invalid.returncode != 2 or "--uid must be a decimal integer" not in invalid.stderr or invalid.stdout:
        fail("non-numeric UID did not fail with exit 2 and stderr diagnostic")

    root_uid = run_helper(helper, ["--uid", "0", "--gid", "100"])
    if root_uid.returncode != 2 or "--uid must be between 1" not in root_uid.stderr or root_uid.stdout:
        fail("UID 0 did not fail with exit 2 and stderr diagnostic")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_identity(root)
        identity = module.rewrite_identity(root, 1234, 100)
        if identity.old_uid != 1000 or identity.old_gid != 1000 or identity.uid != 1234 or identity.gid != 100:
            fail(f"unexpected identity result: {identity}")
        passwd = read(root / "etc/passwd")
        group = read(root / "etc/group")
        if "vscode:x:1234:100:vscode:/home/vscode:/bin/bash\n" not in passwd:
            fail(f"passwd was not rewritten correctly:\n{passwd}")
        if "vscode:x:100:vscode\n" not in group:
            fail(f"group was not rewritten correctly:\n{group}")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_identity(root, extra_passwd="bob:x:1234:1234:bob:/home/bob:/bin/sh\n")
        try:
            module.rewrite_identity(root, 1234, 100)
        except module.ApplyError as exc:
            if "UID 1234 already belongs to user bob" not in str(exc):
                fail(f"unexpected UID conflict diagnostic: {exc}")
        else:
            fail("UID conflict was not rejected")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_identity(root, extra_group="staff:x:100:\n")
        try:
            module.rewrite_identity(root, 1234, 100)
        except module.ApplyError as exc:
            if "GID 100 already belongs to group staff" not in str(exc):
                fail(f"unexpected GID conflict diagnostic: {exc}")
        else:
            fail("GID conflict was not rejected")

    calls: list[tuple[str, str, int, int]] = []
    original_chown_path = module.chown_path
    original_chown_tree = module.chown_tree
    original_chown_matching_tree = module.chown_matching_tree
    original_ensure_runtime_dir = module.ensure_runtime_dir

    def fake_chown_path(path: Path, uid: int, gid: int) -> None:
        calls.append(("path", str(path), uid, gid))

    def fake_chown_tree(path: Path, uid: int, gid: int) -> None:
        calls.append(("tree", str(path), uid, gid))

    def fake_chown_matching_tree(path: Path, identity) -> None:
        calls.append(("matching-tree", str(path), identity.uid, identity.gid))

    def fake_ensure_runtime_dir(root: Path, identity) -> None:
        calls.append(("runtime", str(root / "run/user" / str(identity.uid)), identity.uid, identity.gid))

    try:
        module.chown_path = fake_chown_path
        module.chown_tree = fake_chown_tree
        module.chown_matching_tree = fake_chown_matching_tree
        module.ensure_runtime_dir = fake_ensure_runtime_dir
        module.apply_ownership(Path("/fixture"), module.Identity(old_uid=1000, old_gid=1000, uid=1234, gid=100))
    finally:
        module.chown_path = original_chown_path
        module.chown_tree = original_chown_tree
        module.chown_matching_tree = original_chown_matching_tree
        module.ensure_runtime_dir = original_ensure_runtime_dir

    if ("matching-tree", "/fixture/home/vscode", 1234, 100) not in calls:
        fail(f"home ownership rewrite was not requested: {calls}")
    if ("runtime", "/fixture/run/user/1234", 1234, 100) not in calls:
        fail(f"runtime dir rewrite was not requested: {calls}")
    if ("path", "/fixture/nix/store", 1234, 100) not in calls:
        fail(f"/nix/store top-level chown was not requested: {calls}")
    if ("tree", "/fixture/nix/store", 1234, 100) in calls:
        fail("/nix/store must not be recursively chowned")
    if ("tree", "/fixture/nix/var/nix", 1234, 100) not in calls:
        fail("/nix/var/nix recursive chown was not requested")

    print("set-user-id-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
