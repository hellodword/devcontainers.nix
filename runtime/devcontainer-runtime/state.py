"""Per-container and per-user state, shared by entrypoint, lifecycle hooks, and cache helpers."""

import base64
import errno
import fcntl
import json
import os
import re
import secrets
import socket
import stat
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DEFAULT_SHARED_NIX_CACHE_DIR = "/var/cache/devcontainer-nix"
LOCAL_CACHE_PROBE_TIMEOUT = 0.1
STAGING_MAX_AGE_SECONDS = 7200
NIX32_ALPHABET = "0123456789abcdfghijklmnpqrsvwxyz"
NIX_CACHE_INFO_TEXT = "StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 10\n"
SHARED_CACHE_SUBDIRS = ("nar", "realisations", "build-trace-v2", "log")
LOCAL_CACHE_REPOSITORIES = (
    "ghcr.io/hellodword/nixos-config-cache",
    "ghcr.io/hellodword/devcontainers-nix-cache",
)


def local_cache_repositories() -> tuple[str, ...]:
    repos_file = Path(__file__).resolve().parent / "cache-repositories.json"
    if repos_file.is_file():
        items = json.loads(repos_file.read_text(encoding="utf-8"))
        if isinstance(items, list) and all(isinstance(x, str) and x for x in items):
            return tuple(items)
    return LOCAL_CACHE_REPOSITORIES


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


def on_mount(path: Path, mounts: set[Path]) -> bool:
    return any(path == mount or mount in path.parents for mount in mounts)


def to_nix32_sha256(raw: bytes) -> str:
    if len(raw) != 32:
        raise StateError(f"expected 32-byte SHA-256 digest, got {len(raw)} bytes")
    chars: list[str] = []
    for idx in range(51, -1, -1):
        bit = idx * 5
        byte_idx, bit_offset = bit // 8, bit % 8
        val = (raw[byte_idx] >> bit_offset) | (
            0 if byte_idx >= 31 else (raw[byte_idx + 1] << (8 - bit_offset))
        )
        chars.append(NIX32_ALPHABET[val & 0x1F])
    return "".join(chars)


def normalize_sri_or_nix32_sha256(nar_hash: str) -> str:
    if nar_hash.startswith("sha256:") and len(nar_hash) == 59:
        return nar_hash
    if nar_hash.startswith("sha256-"):
        raw = base64.b64decode(nar_hash.removeprefix("sha256-"))
        return "sha256:" + to_nix32_sha256(raw)
    raise StateError(f"unsupported SHA-256 hash representation: {nar_hash!r}")


def fsync_dir(directory: Path) -> None:
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(directory, flags)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass
    finally:
        os.close(fd)


def create_staging_temp(
    staging_dir: Path, prefix: str, mode: int = 0o644
) -> tuple[int, Path]:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    for _ in range(16):
        candidate = staging_dir / f"{prefix}-{secrets.token_hex(16)}.tmp"
        try:
            fd = os.open(candidate, flags, mode)
            return fd, candidate
        except FileExistsError:
            continue
    raise StateError(f"failed to allocate unique staging file in {staging_dir}")


def publish_immutable_file(tmp_path: Path, dest_path: Path) -> bool:
    try:
        try:
            os.link(tmp_path, dest_path)
            return True
        except FileExistsError:
            return False
        except OSError as exc:
            if exc.errno not in {errno.EPERM, errno.EOPNOTSUPP, errno.ENOSYS}:
                raise
            if dest_path.exists() or dest_path.is_symlink():
                return False
            os.replace(tmp_path, dest_path)
            return True
    finally:
        tmp_path.unlink(missing_ok=True)


def publish_immutable_bytes(
    cache_dir: Path, staging_dir: Path, rel_target: Path, payload: bytes
) -> bool:
    fd, tmp_path = create_staging_temp(staging_dir, "meta", 0o644)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        return publish_immutable_file(tmp_path, cache_dir / rel_target)
    except BaseException:
        tmp_path.unlink(missing_ok=True)
        raise


def sweep_stale_staging(
    staging_dir: Path,
    *,
    max_age_seconds: float = STAGING_MAX_AGE_SECONDS,
    now: float | None = None,
    dry_run: bool = False,
) -> tuple[int, int]:
    if not staging_dir.exists() or staging_dir.is_symlink() or not staging_dir.is_dir():
        return 0, 0
    current = time.time() if now is None else now
    removed_files = 0
    reclaimed_bytes = 0
    try:
        entries = list(os.scandir(staging_dir))
    except OSError:
        return 0, 0
    for entry in entries:
        if not entry.name.endswith(".tmp"):
            continue
        try:
            st = entry.stat(follow_symlinks=False)
        except OSError:
            continue
        if not stat.S_ISREG(st.st_mode):
            continue
        if current - st.st_mtime < max_age_seconds:
            continue
        if not dry_run:
            try:
                os.unlink(entry.path)
            except OSError:
                continue
        removed_files += 1
        reclaimed_bytes += st.st_size
    return removed_files, reclaimed_bytes


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
    external = source == public or on_mount(source, mounts)
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


def parse_cache_endpoint(
    raw_addr: str, env_name: str = "DEVCONTAINER_LOCAL_CACHE_ADDR"
) -> tuple[str, int, str]:
    raw_addr = raw_addr.strip()
    if raw_addr.startswith("["):
        match = re.fullmatch(r"\[([^\]]+)\]:([0-9]+)", raw_addr)
        if match is None:
            raise StateError(f"invalid {env_name}: {raw_addr!r}")
        host, port_text = match.group(1), match.group(2)
        formatted = f"[{host}]:{port_text}"
    else:
        if ":" not in raw_addr:
            raise StateError(f"{env_name} must include host:port, got {raw_addr!r}")
        host, port_text = raw_addr.rsplit(":", 1)
        if not host or not port_text.isdigit():
            raise StateError(f"invalid {env_name}: {raw_addr!r}")
        formatted = f"{host}:{port_text}"
    port = int(port_text, 10)
    if port < 1 or port > 65535:
        raise StateError(f"port out of range in {env_name}: {port}")
    return host, port, formatted


def validate_shared_cache_path(raw_dir: str | Path) -> Path:
    raw_text = str(raw_dir)
    if not raw_text or raw_text != raw_text.strip():
        raise StateError(f"invalid shared Nix cache path: {raw_text!r}")
    if any(ch.isspace() or ch in "?#&%" for ch in raw_text):
        raise StateError(
            f"shared Nix cache path must not contain whitespace or URL query characters: {raw_text!r}"
        )
    path = Path(raw_text)
    if not path.is_absolute() or ".." in path.parts:
        raise StateError(
            f"shared Nix cache path must be an absolute normalized path: {raw_text!r}"
        )
    for candidate in (*reversed(path.parents), path):
        if candidate.is_symlink():
            raise StateError(
                f"shared Nix cache path must not traverse symlinks: {candidate}"
            )
    return path


def _is_plain_dir(path: Path) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode)


def _is_plain_file(path: Path) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISREG(st.st_mode)


def _is_writable_dir(path: Path) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    if not stat.S_ISDIR(st.st_mode) or (st.st_mode & 0o222) == 0:
        return False
    return os.access(path, os.W_OK | os.X_OK)


def has_non_loopback_interface(
    proc_net_dev: Path = Path("/proc/net/dev"),
) -> bool:
    try:
        lines = proc_net_dev.read_text(encoding="utf-8").splitlines()
    except OSError:
        return True
    interfaces = [
        line.split(":", 1)[0].strip()
        for line in lines[2:]
        if ":" in line and line.split(":", 1)[0].strip()
    ]
    if not interfaces:
        return True
    return any(iface != "lo" for iface in interfaces)


def prepare_shared_nix_cache(
    mounts: set[Path],
    post_build_hook: str | None,
    *,
    cache_dir_path: Path | str = DEFAULT_SHARED_NIX_CACHE_DIR,
) -> tuple[str | None, str | None]:
    cache_dir = validate_shared_cache_path(cache_dir_path)
    if not on_mount(cache_dir, mounts):
        return None, None
    if not _is_plain_dir(cache_dir):
        return None, None

    uri = f"file://{cache_dir}?trusted=1&priority=10"

    if _is_writable_dir(cache_dir):
        try:
            for sub in (*SHARED_CACHE_SUBDIRS, ".staging"):
                subdir = cache_dir / sub
                subdir.mkdir(mode=0o755, exist_ok=True)
                if not _is_plain_dir(subdir):
                    return None, None
            info_file = cache_dir / "nix-cache-info"
            if not _is_plain_file(info_file):
                if info_file.is_symlink() or info_file.exists():
                    return None, None
                created = publish_immutable_bytes(
                    cache_dir,
                    cache_dir / ".staging",
                    Path("nix-cache-info"),
                    NIX_CACHE_INFO_TEXT.encode("ascii"),
                )
                if created:
                    fsync_dir(cache_dir)
            sweep_stale_staging(cache_dir / ".staging")
        except OSError:
            return None, None

        return uri, post_build_hook

    # Read-only mount: LocalBinaryCacheStore::init requires nix-cache-info and all cache subdirs.
    if _is_plain_file(cache_dir / "nix-cache-info") and all(
        _is_plain_dir(cache_dir / sub) for sub in SHARED_CACHE_SUBDIRS
    ):
        return uri, None
    return None, None


def probe_tcp_endpoint(host: str, port: int, timeout: float) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def probe_nix_http_cache(host: str, port: int, formatted: str, timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    try:
        with socket.create_connection((host, port), timeout=timeout) as conn:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            conn.settimeout(remaining)
            request = (
                f"GET /nix-cache-info HTTP/1.1\r\n"
                f"Host: {formatted}\r\n"
                f"Connection: close\r\n\r\n"
            ).encode("ascii")
            conn.sendall(request)
            chunks: list[bytes] = []
            total = 0
            while total < 4096:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                conn.settimeout(remaining)
                block = conn.recv(4096 - total)
                if not block:
                    break
                chunks.append(block)
                total += len(block)
    except OSError:
        return False

    raw = b"".join(chunks).decode("utf-8", errors="replace")
    if "\r\n\r\n" in raw:
        head, body = raw.split("\r\n\r\n", 1)
    elif "\n\n" in raw:
        head, body = raw.split("\n\n", 1)
    else:
        return False

    status_line = head.splitlines()[0] if head.splitlines() else ""
    if not re.match(r"^HTTP/1\.[01]\s+200\b", status_line):
        return False
    return any(line.strip() == "StoreDir: /nix/store" for line in body.splitlines())


def _atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}-",
        delete=False,
    ) as handle:
        tmp_path = Path(handle.name)
        try:
            handle.write(content)
            handle.flush()
            os.fchmod(handle.fileno(), 0o644)
            os.replace(tmp_path, path)
        finally:
            tmp_path.unlink(missing_ok=True)


def refresh_local_cache(
    environ: dict[str, str],
    mounts: set[Path] | None = None,
    post_build_hook: str | None = None,
    has_external_net: bool | None = None,
    *,
    shared_cache_dir: Path | str = DEFAULT_SHARED_NIX_CACHE_DIR,
) -> bool:
    home = environ.get("HOME") or "/home/vscode"
    state_home = Path(environ.get("XDG_STATE_HOME") or (Path(home) / ".local/state"))
    state_dir = state_home / "devcontainer"
    conf_path = state_dir / "nix-local-cache.conf"

    active_mounts = mount_points() if mounts is None else mounts
    shared_uri, active_hook = prepare_shared_nix_cache(
        active_mounts, post_build_hook, cache_dir_path=shared_cache_dir
    )

    raw_oranc_addr = environ.get("DEVCONTAINER_LOCAL_CACHE_ADDR", "").strip()
    oranc_target = (
        parse_cache_endpoint(raw_oranc_addr, "DEVCONTAINER_LOCAL_CACHE_ADDR")
        if raw_oranc_addr
        else None
    )

    raw_host_addr = environ.get("DEVCONTAINER_HOST_STORE_CACHE_ADDR", "").strip()
    host_store_target = (
        parse_cache_endpoint(raw_host_addr, "DEVCONTAINER_HOST_STORE_CACHE_ADDR")
        if raw_host_addr
        else None
    )

    oranc_reachable = False
    host_store_reachable = False
    if oranc_target is not None and host_store_target is not None:
        with ThreadPoolExecutor(max_workers=2) as pool:
            fut_oranc = pool.submit(
                probe_tcp_endpoint,
                oranc_target[0],
                oranc_target[1],
                LOCAL_CACHE_PROBE_TIMEOUT,
            )
            fut_host = pool.submit(
                probe_nix_http_cache,
                host_store_target[0],
                host_store_target[1],
                host_store_target[2],
                LOCAL_CACHE_PROBE_TIMEOUT,
            )
            oranc_reachable = fut_oranc.result()
            host_store_reachable = fut_host.result()
    elif oranc_target is not None:
        oranc_reachable = probe_tcp_endpoint(
            oranc_target[0], oranc_target[1], LOCAL_CACHE_PROBE_TIMEOUT
        )
    elif host_store_target is not None:
        host_store_reachable = probe_nix_http_cache(
            host_store_target[0],
            host_store_target[1],
            host_store_target[2],
            LOCAL_CACHE_PROBE_TIMEOUT,
        )

    substituters: list[str] = []
    if shared_uri is not None:
        substituters.append(shared_uri)
    if host_store_reachable and host_store_target is not None:
        substituters.append(f"http://{host_store_target[2]}?trusted=1&priority=20")
    if oranc_reachable and oranc_target is not None:
        substituters.extend(
            f"http://{oranc_target[2]}/{repo}" for repo in local_cache_repositories()
        )

    if not substituters and active_hook is None:
        conf_path.unlink(missing_ok=True)
        return False

    external_net = (
        has_non_loopback_interface() if has_external_net is None else has_external_net
    )
    lines: list[str] = []
    if substituters:
        if not external_net and not host_store_reachable and not oranc_reachable:
            lines.append(f"substituters = {' '.join(substituters)}")
        else:
            lines.append(f"extra-substituters = {' '.join(substituters)}")
    if active_hook is not None:
        lines.append(f"post-build-hook = {active_hook}")
    lines.append("fallback = true")
    lines.append("connect-timeout = 3")
    _atomic_write_text(conf_path, "\n".join(lines) + "\n")
    return True
