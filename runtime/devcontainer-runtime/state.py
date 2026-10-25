"""Per-container and per-user state, shared by entrypoint and lifecycle hooks."""

import fcntl
import os
import re
import secrets
import stat
import tempfile
from pathlib import Path


class StateError(Exception):
    pass


def valid_machine_id(value: str) -> bool:
    return re.fullmatch(r"[0-9a-f]{32}", value) is not None and value != "0" * 32


def requested_machine_id(environ: dict[str, str]) -> str | None:
    value = environ.get("DEVCONTAINER_MACHINE_ID")
    if value is not None and not valid_machine_id(value):
        raise StateError("DEVCONTAINER_MACHINE_ID must be 32 lowercase hexadecimal characters and nonzero")
    return value


def read_machine_id(path: Path, requested: str | None) -> str | None:
    # No symlink following at the writable target, and no arbitrary-size reads.
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
    if requested is not None and value != requested:
        raise StateError("DEVCONTAINER_MACHINE_ID conflicts with the existing machine-id")
    return value


def machine_id_source(root: Path, mounts: set[Path]) -> tuple[Path, bool]:
    public = root / "etc/machine-id"
    target = root / "var/lib/devcontainer/machine-id"
    if public.is_symlink():
        if os.readlink(public) != "/var/lib/devcontainer/machine-id":
            raise StateError("/etc/machine-id must point to /var/lib/devcontainer/machine-id")
        source = target
    else:
        source = public
    external = source == public or any(
        source == mount or mount in source.parents for mount in mounts
    )
    # Refuse redirected state directories even when the leaf is a regular file.
    if source == target and any(parent.is_symlink() for parent in source.parents):
        raise StateError("machine-id state directory must not be a symlink")
    return source, external


def validate_machine_id(root: Path, requested: str | None, mounts: set[Path]) -> None:
    source, external = machine_id_source(root, mounts)
    value = read_machine_id(source, requested)
    if external and value is None:
        raise StateError("mounted /etc/machine-id must contain a valid nonempty machine-id")


def ensure_machine_id(root: Path, requested: str | None, mounts: set[Path]) -> None:
    source, external = machine_id_source(root, mounts)
    value = read_machine_id(source, requested)
    if external:
        if value is None:
            raise StateError("mounted /etc/machine-id must contain a valid nonempty machine-id")
        return
    if value is not None:
        return
    directory = source.parent
    st = directory.stat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid():
        raise StateError("machine-id state directory must be owned by the container user")
    lock = directory / ".machine-id.lock"
    fd = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    with os.fdopen(fd, "wb") as handle:
        st = os.fstat(handle.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid() or st.st_nlink != 1:
            raise StateError("invalid machine-id lock file")
        fcntl.flock(handle, fcntl.LOCK_EX)
        if read_machine_id(source, requested) is not None:
            return
        value = requested or secrets.token_hex(16)
        while not valid_machine_id(value):
            value = secrets.token_hex(16)
        with tempfile.NamedTemporaryFile(dir=directory, prefix=".machine-id-", delete=False) as output:
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
    # Never chmod existing user directories or mounted caches.
    state_home = environ.get("XDG_STATE_HOME") or str(Path(home) / ".local/state")
    (Path(state_home) / "bash").mkdir(mode=0o700, exist_ok=True)
    if runtime_dir is not None:
        path = Path(runtime_dir)
        if not path.is_absolute() or ".." in path.parts:
            raise StateError("XDG_RUNTIME_DIR must be an absolute normalized path")
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        st = path.stat()
        if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.geteuid() or stat.S_IMODE(st.st_mode) != 0o700:
            raise StateError("XDG_RUNTIME_DIR must be owned by the current user with mode 0700")
