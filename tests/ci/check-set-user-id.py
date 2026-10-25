#!/usr/bin/env python3
import importlib.util
import os
import subprocess
import sys
import tempfile
from unittest.mock import patch
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

    def fake_chown_tree(path: Path, uid: int, gid: int, mounts: set[Path]) -> None:
        calls.append(("tree", str(path), uid, gid))

    def fake_chown_matching_tree(path: Path, identity, mounts: set[Path]) -> None:
        calls.append(("matching-tree", str(path), identity.uid, identity.gid))

    def fake_ensure_runtime_dir(root: Path, identity, mounts: set[Path]) -> None:
        calls.append(("runtime", str(root / "run/user" / str(identity.uid)), identity.uid, identity.gid))

    try:
        module.chown_path = fake_chown_path
        module.chown_tree = fake_chown_tree
        module.chown_matching_tree = fake_chown_matching_tree
        module.ensure_runtime_dir = fake_ensure_runtime_dir
        module.apply_ownership(Path("/fixture"), module.Identity(old_uid=1000, old_gid=1000, uid=1234, gid=100), set())
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
    if ("path", "/fixture/nix/store/.links", 1234, 100) not in calls:
        fail("Nix optimiser directory ownership was not updated")
    if ("tree", "/fixture/nix/store/.links", 1234, 100) in calls:
        fail("Nix optimiser hardlink contents must not be chowned")

    # Exercise real traversal with synthetic mount boundaries, including a file
    # mount and a symlink pointing outside the home. No root privileges needed.
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        home = root / "home/vscode"
        mounted = home / "cache with space"
        mounted.mkdir(parents=True)
        (mounted / "data").write_text("retain")
        (home / "config").write_text("mounted file")
        (home / "owned").write_text("owned")
        outside = root / "outside"
        outside.mkdir()
        (outside / "keep").touch()
        (home / "link").symlink_to(outside)
        identity = module.Identity(os.getuid(), os.getgid(), 1234, 100)
        changed = []
        with patch.object(module.os, "chown", side_effect=lambda path, *args, **kwargs: changed.append(Path(path))):
            module.chown_matching_tree(home, identity, {mounted, home / "config"})
        assert home / "owned" in changed
        assert home / "link" in changed
        assert mounted not in changed and mounted / "data" not in changed
        assert home / "config" not in changed and outside / "keep" not in changed
        assert (mounted / "data").read_text() == "retain"
        stale = root / "old-runtime"
        stale.mkdir()
        (stale / "wayland-0").touch()
        module.remove_stale_runtime_dir(stale, identity, set())
        assert (stale / "wayland-0").exists()
        (stale / "wayland-0").unlink()
        module.remove_stale_runtime_dir(stale, identity, {stale})
        assert stale.exists()
        module.remove_stale_runtime_dir(stale, identity, set())
        assert not stale.exists()

        write_identity(root)
        before = read(root / "etc/passwd")
        with patch.object(module, "mount_points", return_value={home}):
            try:
                module.set_user_id(root, 1234, 100)
            except module.ApplyError as exc:
                assert "mounted system path" in str(exc)
            else:
                fail("whole-home mount remapping must fail before account mutation")
        assert read(root / "etc/passwd") == before

        # A failed traversal must leave account IDs unchanged so a restart can
        # retry the old-owned files. Account writes can also resume independently.
        with patch.object(module, "mount_points", return_value=set()):
            with patch.object(module, "apply_ownership", side_effect=module.ApplyError("interrupted ownership")):
                try:
                    module.set_user_id(root, 1234, 100)
                except module.ApplyError:
                    pass
                else:
                    fail("expected synthetic ownership failure")
            assert read(root / "etc/passwd") == before
            original_write_lines = module.write_lines

            def interrupt_group(path, lines):
                if path.name == "group":
                    raise module.ApplyError("interrupted account update")
                original_write_lines(path, lines)

            with patch.object(module, "apply_ownership"), patch.object(module, "write_lines", side_effect=interrupt_group):
                try:
                    module.set_user_id(root, 1234, 100)
                except module.ApplyError:
                    pass
                else:
                    fail("expected synthetic group update failure")
            assert "vscode:x:1234:100:" in read(root / "etc/passwd")
            assert "vscode:x:1000:" in read(root / "etc/group")
            with patch.object(module, "apply_ownership"):
                module.set_user_id(root, 1234, 100)
            assert "vscode:x:100:vscode" in read(root / "etc/group")

    with patch.object(Path, "read_text", return_value="1 0 0:1 / / rw - overlay overlay rw\n2 1 0:2 / /home/cache\\040dir rw - tmpfs tmpfs rw\n"):
        assert module.mount_points() == {Path("/home/cache dir")}

    print("set-user-id-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
