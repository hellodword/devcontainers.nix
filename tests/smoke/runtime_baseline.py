"""Docker lifecycle checks which cannot run through `docker exec bash -lc`."""
import contextlib
import json
import os
import pty
import re
import select
import subprocess
import tempfile
import time
import uuid
from pathlib import Path


class RuntimeChecks:
    def __init__(self, image: str, log):
        self.image = image
        self.log = log

    def docker(self, *args: str, expected: int = 0, timeout: int = 60, input: str | None = None) -> str:
        result = subprocess.run(["docker", *args], input=input, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        if result.returncode != expected:
            raise AssertionError(f"docker {args[0]} exited {result.returncode}, expected {expected}:\n{result.stdout}")
        return result.stdout.strip()

    @contextlib.contextmanager
    def container(self, options=(), command=(), image=None):
        container = self.docker("create", "--network", "none", *options, image or self.image, *command)
        try:
            yield container
        finally:
            self.docker("rm", "-f", container, timeout=30)

    def wait_ready(self, container: str) -> str:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            status = json.loads(self.docker("inspect", "--format", "{{json .State}}", container))
            if not status["Running"]:
                raise AssertionError("container startup failed: " + self.docker("logs", container))
            result = subprocess.run(["docker", "exec", "--user", "vscode", container, "cat", "/etc/machine-id"], capture_output=True, text=True, timeout=10)
            if result.returncode == 0 and re.fullmatch(r"[0-9a-f]{32}\n", result.stdout):
                return result.stdout
            time.sleep(0.1)
        raise AssertionError("container did not finish startup within 30 seconds")

    def once(self, options=(), command=(), expected=0, image=None):
        with self.container(options, command, image) as container:
            self.docker("start", container)
            code = int(self.docker("wait", container, timeout=60))
            output = self.docker("logs", container)
            assert code == expected, f"exit {code}, expected {expected}: {output}"
            return output

    def identity(self, uid: int, gid: int, options=(), image=None, nix=False):
        with self.container(options, image=image) as container:
            self.docker("start", container)
            self.wait_ready(container)
            check = (
                f'test "$(id -u)" = {uid} && test "$(id -g)" = {gid} && '
                'test "$(id -un)" = vscode && test "$(id -gn)" = vscode && '
                'test "$HOME" = /home/vscode && '
                f'test "$(stat -c %u /run/user/{uid})" = {uid} && '
                f'test "$(stat -c %a /run/user/{uid})" = 700 && '
                'test ! -w /home/vscode/.vscode-server/data/Machine/settings.json && '
                'test "$(stat -c %u /home/vscode/.vscode-server/data/Machine/settings.json)" = 0 && '
                'test -w /nix/store && test -w /nix/store/.links && test -w /nix/var/nix/db'
            )
            self.docker("exec", "--user", "vscode", container, "bash", "-c", check)
            if nix:
                probe = Path(__file__).with_name("nix_runtime.py").read_text()
                self.docker("exec", "--user", "vscode", "-i", container, "python3", "-", input=probe, timeout=180)

    def machine_ids(self):
        self.once(command=["bash", "-c", "exit 37"], expected=37)
        self.once(options=["--entrypoint", "/usr/bin/bash"], command=["-c", "test ! -s /var/lib/devcontainer/machine-id && test -L /etc/machine-id"])
        values = []
        for _ in range(2):
            with self.container() as container:
                self.docker("start", container)
                value = self.wait_ready(container)
                self.docker("stop", "--time", "5", container)
                self.docker("start", container)
                assert self.wait_ready(container) == value
                values.append(value)
        assert values[0] != values[1]
        fixed = "1234567890abcdef1234567890abcdef"
        output = self.once(["-e", f"DEVCONTAINER_MACHINE_ID={fixed}"], ["cat", "/etc/machine-id"])
        assert output == fixed
        for value in ["", "0" * 32, "A" * 32, "invalid"]:
            self.once(["-e", f"DEVCONTAINER_MACHINE_ID={value}"], expected=2)
        with tempfile.TemporaryDirectory(prefix="devcontainer-machine-id-") as temporary:
            source = Path(temporary) / "machine-id"
            source.write_text(fixed + "\n")
            source.chmod(0o444)
            before = source.stat()
            mount = ["--mount", f"type=bind,src={source},dst=/etc/machine-id,readonly"]
            assert self.once(mount, ["cat", "/etc/machine-id"]) == fixed
            assert source.stat().st_uid == before.st_uid and source.stat().st_mode == before.st_mode
            self.once([*mount, "-e", "DEVCONTAINER_MACHINE_ID=abcdef1234567890abcdef1234567890"], expected=1)
            source.chmod(0o644)
            source.write_text("")
            self.once(mount, expected=1)
            source.write_text("malformed\n")
            self.once(mount, expected=1)

    def identities(self):
        self.identity(1000, 1000, nix=True)
        for uid, gid, env in [
            (1234, 1000, ["-e", "DEVCONTAINER_UID=1234"]),
            (1000, 1235, ["-e", "DEVCONTAINER_GID=1235"]),
            (1234, 1235, ["-e", "DEVCONTAINER_UID=1234", "-e", "DEVCONTAINER_GID=1235"]),
        ]:
            self.identity(uid, gid, ["--user", "0", *env], nix=True)
        self.once(["--user", "0"], expected=126)
        self.once(["-e", "DEVCONTAINER_UID=1234"], expected=126)
        self.once(["--user", "0", "-e", "DEVCONTAINER_UID=0"], expected=2)
        self.once(["--user", "0", "-e", "DEVCONTAINER_GID=2147483648"], expected=2)
        self.once(["--user", "0", "--entrypoint", "/usr/bin/bash", "-e", "DEVCONTAINER_UID=1234"], ["-c", "printf 'bob:x:1234:1234:bob:/tmp:/bin/sh\\n' >> /etc/passwd; exec /usr/bin/devcontainer-entrypoint true"], expected=1)

        with tempfile.TemporaryDirectory(prefix="devcontainer-bind-") as temporary:
            source = Path(temporary)
            source.chmod(0o755)
            (source / "keep").write_text("host data")
            before = {path.name: (path.stat().st_uid, path.stat().st_gid, path.stat().st_mode) for path in [source, source / "keep"]}
            self.identity(1234, 1235, ["--user", "0", "-e", "DEVCONTAINER_UID=1234", "-e", "DEVCONTAINER_GID=1235", "--mount", f"type=bind,src={source},dst=/home/vscode/.cache/host", "--mount", f"type=bind,src={source},dst=/workspaces/project"])
            after = {path.name: (path.stat().st_uid, path.stat().st_gid, path.stat().st_mode) for path in [source, source / "keep"]}
            assert before == after and (source / "keep").read_text() == "host data"

        # Same helper through the documented build-time route, including UID-only
        # and GID-only changes while keeping the OCI user as vscode.
        with tempfile.TemporaryDirectory(prefix="devcontainer-build-") as temporary:
            context = Path(temporary)
            (context / "Dockerfile").write_text(
                f"FROM {self.image}\nUSER root\nARG DEV_UID=1000\nARG DEV_GID=1000\n"
                "RUN /usr/bin/devcontainer-set-user-id --uid $DEV_UID --gid $DEV_GID\n"
                "ENV XDG_RUNTIME_DIR=/run/user/${DEV_UID}\nUSER vscode\n"
            )
            for uid, gid in [(1234, 1000), (1000, 1235), (1234, 1235)]:
                tag = "devcontainer-runtime-test:" + uuid.uuid4().hex
                try:
                    self.docker("build", "--network", "none", "-t", tag, "--build-arg", f"DEV_UID={uid}", "--build-arg", f"DEV_GID={gid}", str(context), timeout=180)
                    self.identity(uid, gid, image=tag, nix=True)
                    assert self.docker("inspect", "--format", "{{.Config.User}}", tag) == "vscode"
                finally:
                    exists = subprocess.run(["docker", "image", "inspect", tag], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                    if exists.returncode == 0:
                        self.docker("image", "rm", "-f", tag)

    def processes(self):
        for options, expected in [([], "tini"), (["--init"], "docker-init")]:
            with self.container(options) as container:
                self.docker("start", container)
                self.wait_ready(container)
                assert self.docker("exec", container, "cat", "/proc/1/comm") == expected
                script = "import os,time; p=os.fork(); print(p,flush=True) if p else time.sleep(.1)"
                child = self.docker("exec", container, "python3", "-c", script)
                # The child outlives its parent, is adopted and reaped by PID 1.
                self.docker("exec", container, "bash", "-c", f"for i in {{1..50}}; do test ! -e /proc/{child} && exit 0; sleep .1; done; exit 1")
                count = self.docker("exec", container, "bash", "-c", "grep -lx tini /proc/[0-9]*/comm | wc -l")
                assert int(count) == (1 if expected == "tini" else 0)
        command = ["python3", "-c", "import signal,sys,time,pathlib; signal.signal(signal.SIGTERM, lambda *_: sys.exit(23)); pathlib.Path('/tmp/ready').touch(); time.sleep(120)"]
        with self.container(command=command) as container:
            self.docker("start", container)
            self.wait_ready(container)
            self.docker("exec", container, "bash", "-c", "for i in {1..100}; do test -f /tmp/ready && exit 0; sleep .1; done; exit 1")
            self.docker("kill", "--signal", "TERM", container)
            assert self.docker("wait", container) == "23"

    def interactive(self):
        with self.container(["-it"], ["bash", "--noprofile", "--norc", "-i"]) as container:
            master, slave = pty.openpty()
            process = subprocess.Popen(["docker", "start", "-ai", container], stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
            os.close(slave)
            transcript = bytearray()

            def until(marker: bytes):
                deadline = time.monotonic() + 30
                while marker not in transcript and time.monotonic() < deadline:
                    if select.select([master], [], [], 0.2)[0]:
                        transcript.extend(os.read(master, 65536))
                assert marker in transcript, transcript.decode(errors="replace")

            try:
                os.write(master, b"printf 'READY_%s\\n' OK\n")
                until(b"READY_OK")
                os.write(master, b"sleep 1000\n")
                time.sleep(0.3)
                os.write(master, b"\x03")
                os.write(master, b"printf 'CTRL_%s\\n' OK\nexit 37\n")
                until(b"CTRL_OK")
                process.wait(timeout=30)
                assert self.docker("inspect", "--format", "{{.State.ExitCode}}", container) == "37"
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=10)
                os.close(master)

    def sessions(self):
        self.once(["-e", "XDG_RUNTIME_DIR=/tmp/custom-runtime"], ["bash", "-c", 'test "$XDG_RUNTIME_DIR" = /tmp/custom-runtime && test "$(stat -c %a "$XDG_RUNTIME_DIR")" = 700'])
        self.once(["-e", "XDG_RUNTIME_DIR=relative"], expected=1)
        code = (
            "import os,re,subprocess,time; "
            "assert 'DBUS_SESSION_BUS_ADDRESS' not in os.environ; "
            "out=subprocess.check_output(['dbus-run-session','--','dbus-send','--session','--print-reply','--dest=org.freedesktop.DBus','/org/freedesktop/DBus','org.freedesktop.DBus.GetConnectionUnixProcessID','string:org.freedesktop.DBus'],text=True); "
            "pid=re.search(r'uint32 (\\d+)',out)[1]; "
            "time.sleep(.1); assert not os.path.exists('/proc/'+pid)"
        )
        self.once(command=["python3", "-c", code])

    def run(self):
        for check in [self.machine_ids, self.identities, self.processes, self.interactive, self.sessions]:
            print(f"runtime baseline: {check.__name__}", flush=True)
            self.log.write(f"{check.__name__}\n")
            self.log.flush()
            check()


def run_runtime_checks(image: str, log_dir: Path) -> int:
    with (log_dir / "runtime-baseline.log").open("w") as log:
        try:
            RuntimeChecks(image, log).run()
        except (AssertionError, OSError, subprocess.SubprocessError) as exc:
            log.write(str(exc) + "\n")
            print(f"runtime baseline failed: {exc}")
            return 1
    return 0
