#!/usr/bin/env python3
import importlib.util
import multiprocessing
import os
import stat
import subprocess
import sys
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


def load_helper(path: Path):
    loader = SourceFileLoader("devcontainer_runtime", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fixture(root: Path) -> None:
    (root / "etc").mkdir(parents=True)
    (root / "var/lib/devcontainer").mkdir(parents=True)
    (root / "var/lib/devcontainer/machine-id").touch(mode=0o444)
    (root / "etc/machine-id").symlink_to("/var/lib/devcontainer/machine-id")


def expect_error(error, call, message: str) -> None:
    try:
        call()
    except error as exc:
        assert message in str(exc), str(exc)
    else:
        raise AssertionError(f"expected failure containing: {message}")


def unchanged_file(path: Path, before) -> None:
    after = path.stat()
    assert (after.st_ino, after.st_mtime_ns, after.st_mode, after.st_uid, after.st_gid) == (
        before.st_ino, before.st_mtime_ns, before.st_mode, before.st_uid, before.st_gid
    )


def check_startup_order(runtime) -> None:
    class ExecReached(Exception):
        pass

    for pid, image_uid, configured, expected_runtime in [
        (1, 1000, "/run/user/1000", "/run/user/1234"),
        (2, 1500, "/run/user/1500", "/run/user/1234"),
        (1, 1000, "/custom/runtime", "/custom/runtime"),
    ]:
        current = {"uid": 0, "gid": 0}
        events = []
        account = SimpleNamespace(pw_uid=image_uid, pw_gid=1000, pw_dir="/home/vscode")

        def drop_uid(uid):
            assert current["gid"] == 1000
            current["uid"] = uid
            events.append("drop")

        def prepare(*args):
            assert current["uid"] == 1234 and current["gid"] == 1000
            events.append("prepare")

        def execute(binary, argv):
            assert current["uid"] == 1234
            assert argv[-3:] == ["printf", "%s", "two words"]
            assert binary.endswith("/bin/tini" if pid == 1 else "/bin/bash")
            if pid == 1:
                assert argv[1:3] == ["-g", "--"]
            raise ExecReached()

        with (
            patch.dict(os.environ, {"HOME": "/home/vscode", "DEVCONTAINER_UID": "1234", "XDG_RUNTIME_DIR": configured}, clear=True),
            patch.object(runtime.pwd, "getpwnam", return_value=account),
            patch.object(runtime.identity, "mount_points", return_value=set()),
            patch.object(runtime.identity, "set_user_id", side_effect=lambda *args: events.append("identity")),
            patch.object(runtime.state, "validate_machine_id", side_effect=lambda *args: events.append("validate")),
            patch.object(runtime.state, "ensure_xdg", side_effect=prepare),
            patch.object(runtime.state, "ensure_machine_id", side_effect=prepare),
            patch.object(runtime.os, "geteuid", side_effect=lambda: current["uid"]),
            patch.object(runtime.os, "getegid", side_effect=lambda: current["gid"]),
            patch.object(runtime.os, "getpid", return_value=pid),
            patch.object(runtime.os, "setgroups", side_effect=lambda groups: events.append(("groups", groups))),
            patch.object(runtime.os, "setgid", side_effect=lambda gid: current.update(gid=gid)),
            patch.object(runtime.os, "setuid", side_effect=drop_uid),
            patch.object(Path, "read_text", return_value='{"runtimeDir":"/run/user/1000"}'),
            patch.object(runtime.os, "execv", side_effect=execute),
        ):
            try:
                runtime.main(["printf", "%s", "two words"])
            except ExecReached:
                pass
            else:
                raise AssertionError("startup did not reach exec")
            assert events == ["validate", "identity", ("groups", []), "drop", "prepare", "prepare"]
            assert os.environ["XDG_RUNTIME_DIR"] == expected_runtime
            assert os.environ["USER"] == "vscode" and os.environ["HOME"] == "/home/vscode"


def main() -> int:
    helper = Path(os.environ["DEVCONTAINER_RUNTIME"]) / "bin/devcontainer-runtime"
    runtime = load_helper(helper)
    check_startup_order(runtime)
    state = runtime.state
    fixed = "1234567890abcdef1234567890abcdef"
    other = "abcdef1234567890abcdef1234567890"

    for invalid in ["", "0" * 32, "A" * 32, "1" * 31, "1" * 33, fixed + "\n"]:
        expect_error(state.StateError, lambda: state.requested_machine_id({"DEVCONTAINER_MACHINE_ID": invalid}), "32 lowercase")

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        fixture(root)
        target = root / "var/lib/devcontainer/machine-id"
        assert target.read_bytes() == b""
        state.ensure_machine_id(root, fixed, set())
        before = target.stat()
        assert target.read_text() == fixed + "\n"
        assert stat.S_IMODE(before.st_mode) == 0o444
        state.ensure_machine_id(root, None, set())
        state.ensure_machine_id(root, fixed, set())
        unchanged_file(target, before)
        expect_error(state.StateError, lambda: state.ensure_machine_id(root, other, set()), "conflicts")
        unchanged_file(target, before)
        target.unlink()
        target.write_text("malformed\n")
        expect_error(state.StateError, lambda: state.ensure_machine_id(root, fixed, set()), "invalid nonempty")
        assert target.read_text() == "malformed\n"

    generated = []
    for _ in range(2):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture(root)
            processes = [multiprocessing.get_context("fork").Process(target=state.ensure_machine_id, args=(root, None, set())) for _ in range(8)]
            for process in processes:
                process.start()
            for process in processes:
                process.join(timeout=10)
                if process.is_alive():
                    process.kill()
                    process.join()
                    raise AssertionError("machine-id generation deadlocked")
                assert process.exitcode == 0
            value = (root / "var/lib/devcontainer/machine-id").read_text().strip()
            assert state.valid_machine_id(value)
            generated.append(value)
            assert not list((root / "var/lib/devcontainer").glob(".machine-id-*"))
    assert generated[0] != generated[1]

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        fixture(root)
        target = root / "var/lib/devcontainer/machine-id"
        # OCI runtimes may resolve the public symlink before bind-mounting.
        expect_error(state.StateError, lambda: state.ensure_machine_id(root, None, {target}), "nonempty")
        public = root / "etc/machine-id"
        public.unlink()
        public.write_text(fixed + "\n")
        public.chmod(0o444)
        before = public.stat()
        state.ensure_machine_id(root, fixed, {public})
        unchanged_file(public, before)
        assert target.read_bytes() == b""
        expect_error(state.StateError, lambda: state.ensure_machine_id(root, other, {public}), "conflicts")
        target.unlink()
        target.symlink_to(public)
        public.unlink()
        public.symlink_to("/var/lib/devcontainer/machine-id")
        expect_error(OSError, lambda: state.ensure_machine_id(root, None, set()), "")

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        home = root / "home"
        cache = root / "mounted-cache"
        cache.mkdir(mode=0o777)
        (cache / "keep").write_text("cache payload")
        before = cache.stat()
        runtime_dir = root / "run"
        env = {"HOME": str(home), "XDG_CACHE_HOME": str(cache)}
        state.ensure_xdg(env, str(runtime_dir))
        assert (home / ".local/state/bash").is_dir()
        assert cache.stat() == before
        assert (cache / "keep").read_text() == "cache payload"
        assert stat.S_IMODE(runtime_dir.stat().st_mode) == 0o700
        state.ensure_xdg(env, str(runtime_dir))
        runtime_dir.chmod(0o755)
        expect_error(state.StateError, lambda: state.ensure_xdg(env, str(runtime_dir)), "mode 0700")
        assert stat.S_IMODE(runtime_dir.stat().st_mode) == 0o755
        runtime_dir.chmod(0o700)
        alias = root / "runtime-alias"
        alias.symlink_to(runtime_dir)
        state.ensure_xdg(env, str(alias))
        assert alias.is_symlink()
        expect_error(state.StateError, lambda: state.ensure_xdg(env, "relative"), "absolute")
        expect_error(state.StateError, lambda: state.ensure_xdg({**env, "XDG_STATE_HOME": "relative"}), "absolute")

    # Startup must not run Python/shell hooks supplied through the environment.
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        marker = root / "executed"
        (root / "sitecustomize.py").write_text(f"open({str(marker)!r}, 'w').close()\n")
        bash_env = root / "bash-env"
        bash_env.write_text(f"touch '{marker}'\n")
        result = subprocess.run([str(helper)], env={**os.environ, "PYTHONPATH": str(root), "BASH_ENV": str(bash_env), "DEVCONTAINER_MACHINE_ID": "invalid"}, capture_output=True, text=True)
        assert result.returncode == 2, result.stderr
        assert not marker.exists()

    print("runtime-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
