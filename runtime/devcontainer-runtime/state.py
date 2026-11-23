"""Per-container and per-user state, shared by entrypoint and lifecycle hooks."""

import fcntl
import os
import re
import secrets
import socket
import stat
import tempfile
from pathlib import Path

DEFAULT_LOCAL_CACHE_ADDR = "172.17.0.1:37515"
LOCAL_CACHE_REPOSITORIES = (
    "ghcr.io/hellodword/nixos-config-cache",
    "ghcr.io/hellodword/devcontainers-nix-cache",
)


class StateError(Exception):
    pass


def valid_machine_id(value: str) -> bool:
    return re.fullmatch(r"[0-9a-f]{32}", value) is not None and value != "0" * 32


def mount_points() -> set[Path]:
    def unescape(value: str) -> str:
        return re.sub(r"\\([0-7]{3})", lambda match: chr(int(match[1], 8)), value)

    return {
        Path(unescape(line.split()[4]))
        for line in Path("/proc/self/mountinfo")
        .read_text(encoding="utf-8")
        .splitlines()
        if line.split()[4] != "/"
    }


def read_machine_id(path: Path) -> str | None:
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    with os.fdopen(fd, "rb") as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise StateError(f"machine-id must be a regular file: {path}")
        data = handle.read(34)
    if data == b"":
        return None
    try:
        value = data.removesuffix(b"\n").decode("ascii")
    except UnicodeDecodeError:
        value = ""
    if not valid_machine_id(value):
        raise StateError(f"invalid nonempty machine-id at {path}")
    return value


def machine_id_source(root: Path, mounts: set[Path]) -> tuple[Path, bool]:
    public = root / "etc/machine-id"
    target = root / "var/lib/devcontainer/machine-id"
    if public.is_symlink():
        if os.readlink(public) != "/var/lib/devcontainer/machine-id":
            raise StateError(
                "/etc/machine-id must point to /var/lib/devcontainer/machine-id"
            )
        source = target
    else:
        source = public
    external = source == public or any(
        source == mount or mount in source.parents for mount in mounts
    )
    if source == target and any(parent.is_symlink() for parent in source.parents):
        raise StateError("machine-id state directory must not be a symlink")
    return source, external


def validate_machine_id(root: Path, mounts: set[Path]) -> None:
    source, external = machine_id_source(root, mounts)
    value = read_machine_id(source)
    if external and value is None:
        raise StateError(
            "mounted /etc/machine-id must contain a valid nonempty machine-id"
        )


def ensure_machine_id(root: Path, mounts: set[Path]) -> None:
    source, external = machine_id_source(root, mounts)
    value = read_machine_id(source)
    if external:
        if value is None:
            raise StateError(
                "mounted /etc/machine-id must contain a valid nonempty machine-id"
            )
        return
    if value is not None:
        return
    directory = source.parent
    st = directory.stat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid():
        raise StateError(
            "machine-id state directory must be owned by the container user"
        )
    lock = directory / ".machine-id.lock"
    fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    with os.fdopen(fd, "wb") as handle:
        st = os.fstat(handle.fileno())
        if (
            not stat.S_ISREG(st.st_mode)
            or st.st_uid != os.geteuid()
            or st.st_nlink != 1
        ):
            raise StateError("invalid machine-id lock file")
        fcntl.flock(handle, fcntl.LOCK_EX)
        if read_machine_id(source) is not None:
            return
        value = secrets.token_hex(16)
        while not valid_machine_id(value):
            value = secrets.token_hex(16)
        with tempfile.NamedTemporaryFile(
            dir=directory, prefix=".machine-id-", delete=False
        ) as output:
            temporary = Path(output.name)
            try:
                output.write((value + "\n").encode("ascii"))
                output.flush()
                os.fchmod(output.fileno(), 0o444)
                os.fsync(output.fileno())
                os.replace(temporary, source)
            finally:
                temporary.unlink(missing_ok=True)


def ensure_xdg(environ: dict[str, str], runtime_dir: str | None = None) -> None:
    home = environ.get("HOME", "")
    for name, suffix in {
        "XDG_CONFIG_HOME": ".config",
        "XDG_CACHE_HOME": ".cache",
        "XDG_DATA_HOME": ".local/share",
        "XDG_STATE_HOME": ".local/state",
    }.items():
        value = environ.get(name) or (str(Path(home) / suffix) if home else "")
        if not value or not Path(value).is_absolute():
            raise StateError(f"{name} must be an absolute path (or HOME must be set)")
        Path(value).mkdir(parents=True, exist_ok=True)
    state_home = environ.get("XDG_STATE_HOME") or str(Path(home) / ".local/state")
    (Path(state_home) / "bash").mkdir(mode=0o700, exist_ok=True)
    (Path(state_home) / "devcontainer").mkdir(mode=0o755, exist_ok=True)
    if runtime_dir is not None:
        path = Path(runtime_dir)
        if not path.is_absolute() or ".." in path.parts:
            raise StateError("XDG_RUNTIME_DIR must be an absolute normalized path")
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        st = path.stat()
        if (
            not stat.S_ISDIR(st.st_mode)
            or st.st_uid != os.geteuid()
            or stat.S_IMODE(st.st_mode) != 0o700
        ):
            raise StateError(
                "XDG_RUNTIME_DIR must be owned by the current user with mode 0700"
            )


def parse_cache_endpoint(raw_addr: str) -> tuple[str, int, str]:
    raw_addr = raw_addr.strip()
    if raw_addr.startswith("["):
        match = re.fullmatch(r"\[([^\]]+)\]:([0-9]+)", raw_addr)
        if match is None:
            raise StateError(f"invalid DEVCONTAINER_LOCAL_CACHE_ADDR: {raw_addr!r}")
        host, port_text = match.group(1), match.group(2)
        formatted = f"[{host}]:{port_text}"
    else:
        if ":" not in raw_addr:
            raise StateError(
                f"DEVCONTAINER_LOCAL_CACHE_ADDR must include host:port, got {raw_addr!r}"
            )
        host, port_text = raw_addr.rsplit(":", 1)
        if not host or not port_text.isdigit():
            raise StateError(f"invalid DEVCONTAINER_LOCAL_CACHE_ADDR: {raw_addr!r}")
        formatted = f"{host}:{port_text}"
    port = int(port_text, 10)
    if port < 1 or port > 65535:
        raise StateError(f"port out of range in DEVCONTAINER_LOCAL_CACHE_ADDR: {port}")
    return host, port, formatted


def refresh_local_cache(environ: dict[str, str]) -> bool:
    home = environ.get("HOME") or "/home/vscode"
    state_home = Path(environ.get("XDG_STATE_HOME") or (Path(home) / ".local/state"))
    conf_path = state_home / "devcontainer" / "nix-local-cache.conf"

    probe_flag = environ.get("DEVCONTAINER_LOCAL_CACHE_PROBE", "1").strip().lower()
    if probe_flag in {"0", "false", "no", "off"}:
        conf_path.unlink(missing_ok=True)
        return False

    raw_addr = environ.get("DEVCONTAINER_LOCAL_CACHE_ADDR", DEFAULT_LOCAL_CACHE_ADDR)
    host, port, formatted = parse_cache_endpoint(raw_addr)

    reachable = False
    try:
        with socket.create_connection((host, port), timeout=0.1):
            reachable = True
    except OSError:
        reachable = False

    if not reachable:
        conf_path.unlink(missing_ok=True)
        return False

    conf_path.parent.mkdir(parents=True, exist_ok=True)
    substituters = " ".join(
        f"http://{formatted}/{repo}" for repo in LOCAL_CACHE_REPOSITORIES
    )
    content = (
        f"extra-substituters = {substituters}\nfallback = true\nconnect-timeout = 3\n"
    )
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=conf_path.parent,
        prefix=".nix-local-cache-",
        delete=False,
    ) as handle:
        tmp_path = Path(handle.name)
        try:
            handle.write(content)
            handle.flush()
            os.fchmod(handle.fileno(), 0o644)
            os.replace(tmp_path, conf_path)
        finally:
            tmp_path.unlink(missing_ok=True)
    return True
