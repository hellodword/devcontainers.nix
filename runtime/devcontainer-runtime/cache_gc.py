"""Symlink-safe online and idle garbage collection driven by data/cache-layout.json."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

try:
    import devcontainer_state as state
except ImportError:
    import state  # type: ignore[no-redef]

DEFAULT_GRACE_SECONDS = 600.0
MOUNT_ID_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
SUPPORTED_STRATEGIES = {
    "nix-tombstone",
    "cargo",
    "uv",
    "npm",
    "gradle",
    "idle-age-and-quota",
    "idle-quota-reset",
    "manual",
}
GRADLE_RECLAIMABLE_SUBDIRS = (
    "caches",
    "daemon",
    "wrapper/dists",
    "native",
    ".tmp",
)


@dataclass(frozen=True)
class NarInfoEntry:
    path: Path
    store_hash: str
    nar_name: str
    mtime: float
    info_size: int


def default_cache_layout_path() -> Path:
    here = Path(__file__).resolve().parent
    colocated = here / "cache-layout.json"
    if colocated.is_file():
        return colocated
    repo_candidate = here.parent.parent / "data" / "cache-layout.json"
    if repo_candidate.is_file():
        return repo_candidate
    return Path("/usr/share/devcontainer/cache-layout.json")


def load_cache_layout(layout_path: Path | None = None) -> list[dict]:
    path = layout_path or default_cache_layout_path()
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or data.get("version") != 1:
        raise ValueError(f"Unsupported cache layout version in {path}")
    mounts = data.get("mounts")
    if not isinstance(mounts, list) or not mounts:
        raise ValueError(f"Empty or invalid mounts in {path}")

    seen_ids: set[str] = set()
    validated: list[dict] = []
    for item in mounts:
        if not isinstance(item, dict):
            raise TypeError(f"Invalid mount entry in {path}: {item!r}")
        mount_id = item.get("id")
        target = item.get("target")
        prune_spec = item.get("prune")
        if not isinstance(mount_id, str) or not MOUNT_ID_RE.match(mount_id):
            raise ValueError(f"Invalid mount id in {path}: {mount_id!r}")
        if mount_id in seen_ids:
            raise ValueError(f"Duplicate mount id in {path}: {mount_id!r}")
        seen_ids.add(mount_id)
        if (
            not isinstance(target, str)
            or not target.startswith("/")
            or ".." in Path(target).parts
        ):
            raise ValueError(f"Invalid target path for {mount_id}: {target!r}")
        if not isinstance(prune_spec, dict):
            raise TypeError(f"Missing prune policy for {mount_id}")
        strategy = prune_spec.get("strategy")
        if strategy not in SUPPORTED_STRATEGIES:
            raise ValueError(f"Unsupported prune strategy for {mount_id}: {strategy!r}")
        validated.append(item)
    return validated


def _is_plain_dir(path: Path) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode)


def _unlock_plain_dir_mode(path: Path) -> None:
    flags = os.O_RDONLY | os.O_CLOEXEC
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except OSError:
        return
    try:
        st = os.fstat(fd)
        if stat.S_ISDIR(st.st_mode) and (stat.S_IMODE(st.st_mode) & 0o700) != 0o700:
            os.fchmod(fd, stat.S_IMODE(st.st_mode) | 0o700)
    except OSError:
        pass
    finally:
        os.close(fd)


def tree_bytes(root: Path, *, dry_run: bool = False) -> int:
    if not _is_plain_dir(root):
        return 0
    total = 0
    stack = [root]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(current))
        except PermissionError:
            if dry_run:
                continue
            _unlock_plain_dir_mode(current)
            try:
                entries = list(os.scandir(current))
            except OSError:
                continue
        except OSError:
            continue
        for entry in entries:
            try:
                st = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISLNK(st.st_mode):
                continue
            if stat.S_ISDIR(st.st_mode):
                stack.append(Path(entry.path))
            elif stat.S_ISREG(st.st_mode):
                total += st.st_size
    return total


def safe_remove_entry(target: Path, *, dry_run: bool) -> int:
    try:
        st = os.lstat(target)
    except OSError:
        return 0

    if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode):
        size = st.st_size if stat.S_ISREG(st.st_mode) else 0
        if not dry_run:
            try:
                os.unlink(target)
            except PermissionError:
                _unlock_plain_dir_mode(target.parent)
                try:
                    os.unlink(target)
                except OSError:
                    return 0
            except OSError:
                return 0
        return size

    reclaimed = 0
    if not dry_run:
        _unlock_plain_dir_mode(target)
    try:
        children = list(os.scandir(target))
    except OSError:
        return 0
    for child in children:
        reclaimed += safe_remove_entry(Path(child.path), dry_run=dry_run)
    if not dry_run:
        try:
            os.rmdir(target)
        except OSError:
            pass
    return reclaimed


def safe_clear_dir_contents(directory: Path, *, dry_run: bool) -> int:
    if not _is_plain_dir(directory):
        return 0
    if not dry_run:
        _unlock_plain_dir_mode(directory)
    try:
        children = list(os.scandir(directory))
    except OSError:
        return 0
    reclaimed = 0
    for child in children:
        reclaimed += safe_remove_entry(Path(child.path), dry_run=dry_run)
    return reclaimed


def _parse_narinfo_file(path: Path, st: os.stat_result) -> NarInfoEntry | None:
    try:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            text = handle.read(65536)
    except OSError:
        return None
    nar_name = ""
    for raw_line in text.splitlines():
        if raw_line.startswith("URL:"):
            url = raw_line.split(":", 1)[1].strip()
            if url.startswith("nar/") and "/" not in url.removeprefix("nar/"):
                nar_name = url.removeprefix("nar/")
            break
    if not nar_name:
        return None
    return NarInfoEntry(
        path=path,
        store_hash=path.name.removesuffix(".narinfo"),
        nar_name=nar_name,
        mtime=st.st_mtime,
        info_size=st.st_size,
    )


def prune_nix_cache(
    cache_dir: Path,
    *,
    max_age_days: float,
    max_bytes: int,
    grace_seconds: float,
    idle: bool,
    dry_run: bool,
    now: float,
) -> dict:
    if not _is_plain_dir(cache_dir):
        return {"present": False, "strategy": "nix-tombstone", "reclaimedBytes": 0}

    staging_dir = cache_dir / ".staging"
    nar_dir = cache_dir / "nar"
    if not dry_run and os.access(cache_dir, os.W_OK | os.X_OK):
        staging_dir.mkdir(mode=0o755, exist_ok=True)

    stale_tmp_count, stale_tmp_bytes = state.sweep_stale_staging(
        staging_dir,
        max_age_seconds=max(grace_seconds, state.STAGING_MAX_AGE_SECONDS),
        now=now,
        dry_run=dry_run,
    )

    nar_files: dict[str, tuple[Path, int, float]] = {}
    if _is_plain_dir(nar_dir):
        try:
            for entry in os.scandir(nar_dir):
                try:
                    st = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISLNK(st.st_mode):
                    if not dry_run:
                        try:
                            os.unlink(entry.path)
                        except OSError:
                            pass
                    continue
                if stat.S_ISREG(st.st_mode):
                    nar_files[entry.name] = (
                        Path(entry.path),
                        st.st_size,
                        max(st.st_ctime, st.st_mtime),
                    )
        except OSError:
            pass

    narinfos: list[NarInfoEntry] = []
    try:
        for entry in os.scandir(cache_dir):
            if not entry.name.endswith(".narinfo"):
                continue
            try:
                st = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISLNK(st.st_mode):
                if not dry_run:
                    try:
                        os.unlink(entry.path)
                    except OSError:
                        pass
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            parsed = _parse_narinfo_file(Path(entry.path), st)
            if parsed is not None:
                narinfos.append(parsed)
    except OSError:
        pass

    evicted: list[NarInfoEntry] = []
    surviving: list[NarInfoEntry] = []
    age_cutoff = max_age_days * 86400.0
    for rec in narinfos:
        if max_age_days > 0 and (now - rec.mtime) > age_cutoff:
            evicted.append(rec)
        else:
            surviving.append(rec)

    if max_bytes > 0:
        low_watermark = int(max_bytes * 0.8)

        def referenced_bytes(items: list[NarInfoEntry]) -> int:
            unique_nars = {item.nar_name for item in items}
            return sum(
                nar_files[name][1] for name in unique_nars if name in nar_files
            ) + sum(item.info_size for item in items)

        if referenced_bytes(surviving) > max_bytes:
            surviving.sort(key=lambda item: (item.mtime, item.store_hash))
            while surviving and referenced_bytes(surviving) > low_watermark:
                evicted.append(surviving.pop(0))

    reclaimed_bytes = stale_tmp_bytes
    tombstoned_count = 0
    unlinked_info_count = 0

    for rec in evicted:
        if idle:
            unlinked_info_count += 1
            reclaimed_bytes += rec.info_size
            if not dry_run:
                rec.path.unlink(missing_ok=True)
        else:
            tombstoned_count += 1
            if not dry_run and _is_plain_dir(staging_dir):
                tombstone = staging_dir / f"gc-{rec.store_hash}.narinfo"
                try:
                    os.replace(rec.path, tombstone)
                    os.utime(tombstone, (now, now))
                except OSError:
                    pass

    protected_nars = {rec.nar_name for rec in surviving}
    expired_tombstones = 0
    if _is_plain_dir(staging_dir):
        try:
            for entry in os.scandir(staging_dir):
                if not (
                    entry.name.startswith("gc-") and entry.name.endswith(".narinfo")
                ):
                    continue
                try:
                    st = entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISLNK(st.st_mode):
                    if not dry_run:
                        try:
                            os.unlink(entry.path)
                        except OSError:
                            pass
                    continue
                if not stat.S_ISREG(st.st_mode):
                    continue
                if not idle and (now - st.st_mtime) < grace_seconds:
                    parsed = _parse_narinfo_file(Path(entry.path), st)
                    if parsed is not None:
                        protected_nars.add(parsed.nar_name)
                else:
                    expired_tombstones += 1
                    reclaimed_bytes += st.st_size
                    if not dry_run:
                        try:
                            os.unlink(entry.path)
                        except OSError:
                            pass
        except OSError:
            pass

    if not idle and dry_run:
        for rec in evicted:
            protected_nars.add(rec.nar_name)

    removed_nars = 0
    for nar_name, (nar_path, nar_size, nar_ctime) in nar_files.items():
        if nar_name in protected_nars:
            continue
        if not idle and (now - nar_ctime) < grace_seconds:
            continue
        removed_nars += 1
        reclaimed_bytes += nar_size
        if not dry_run:
            nar_path.unlink(missing_ok=True)

    return {
        "present": True,
        "strategy": "nix-tombstone",
        "evictedNarinfos": len(evicted),
        "tombstonedNarinfos": tombstoned_count,
        "removedNarinfos": unlinked_info_count + expired_tombstones,
        "removedNars": removed_nars,
        "removedStaleTemps": stale_tmp_count,
        "survivingNarinfos": len(surviving),
        "reclaimedBytes": reclaimed_bytes,
    }


_AUTO_UV_BIN = object()


def _find_uv_binary() -> str | None:
    on_path = shutil.which("uv")
    if on_path:
        return on_path
    candidates = sorted(Path("/nix/store").glob("*-uv-*/bin/uv"))
    for candidate in reversed(candidates):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def prune_uv_cache(
    uv_dir: Path,
    *,
    max_bytes: int,
    idle: bool,
    dry_run: bool,
    uv_bin: str | None | object = _AUTO_UV_BIN,
) -> dict:
    if not _is_plain_dir(uv_dir):
        return {"present": False, "strategy": "uv", "reclaimedBytes": 0}
    before = tree_bytes(uv_dir, dry_run=dry_run)
    ran_uv_prune = False
    resolved_uv = _find_uv_binary() if uv_bin is _AUTO_UV_BIN else uv_bin
    if isinstance(resolved_uv, str) and resolved_uv and not dry_run:
        clean_env = {"PATH": "/usr/bin:/bin", "HOME": "/tmp", "UV_NO_CONFIG": "1"}
        res = subprocess.run(
            [
                resolved_uv,
                "cache",
                "prune",
                "--ci",
                "--no-config",
                "--offline",
                "--quiet",
                "--cache-dir",
                str(uv_dir),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=clean_env,
            check=False,
        )
        ran_uv_prune = res.returncode == 0

    after = tree_bytes(uv_dir, dry_run=dry_run)
    reclaimed = max(0, before - after)
    reset = False
    if idle and max_bytes > 0 and after > max_bytes:
        reclaimed += safe_clear_dir_contents(uv_dir, dry_run=dry_run)
        reset = True
    return {
        "present": True,
        "strategy": "uv",
        "uvPruneExecuted": ran_uv_prune,
        "quotaReset": reset,
        "reclaimedBytes": reclaimed,
    }


def prune_expired_files(
    directory: Path, *, max_age_days: float, dry_run: bool, now: float
) -> int:
    if not _is_plain_dir(directory) or max_age_days <= 0:
        return 0
    cutoff = max_age_days * 86400.0
    reclaimed = 0
    try:
        entries = list(os.scandir(directory))
    except OSError:
        return 0
    for entry in entries:
        child = Path(entry.path)
        try:
            st = entry.stat(follow_symlinks=False)
        except OSError:
            continue
        if stat.S_ISLNK(st.st_mode):
            if not dry_run:
                try:
                    os.unlink(child)
                except OSError:
                    pass
            continue
        if stat.S_ISDIR(st.st_mode):
            reclaimed += prune_expired_files(
                child, max_age_days=max_age_days, dry_run=dry_run, now=now
            )
            if not dry_run:
                try:
                    os.rmdir(child)
                except OSError:
                    pass
        elif stat.S_ISREG(st.st_mode) and (now - st.st_mtime) > cutoff:
            reclaimed += safe_remove_entry(child, dry_run=dry_run)
    return reclaimed


def _dir_reference_mtime(directory: Path, fallback_mtime: float) -> float:
    marker = directory / ".cargo-ok"
    try:
        st = os.lstat(marker)
        if stat.S_ISREG(st.st_mode):
            return st.st_mtime
    except OSError:
        pass
    return fallback_mtime


def prune_cargo_cache(
    cargo_home: Path,
    *,
    max_age_days: float,
    max_bytes: int,
    idle: bool,
    dry_run: bool,
    now: float,
) -> dict:
    if not _is_plain_dir(cargo_home):
        return {"present": False, "strategy": "cargo", "reclaimedBytes": 0}
    if not idle:
        return {
            "present": True,
            "strategy": "cargo",
            "skipped": "active_containers",
            "reclaimedBytes": 0,
        }

    reclaimed = 0
    removed_trees = 0
    removed_crates = 0
    cutoff = max_age_days * 86400.0

    for unpacked_parent in (
        cargo_home / "registry" / "src",
        cargo_home / "git" / "checkouts",
    ):
        if not _is_plain_dir(unpacked_parent):
            continue
        try:
            index_dirs = list(os.scandir(unpacked_parent))
        except OSError:
            continue
        for idx_entry in index_dirs:
            idx_path = Path(idx_entry.path)
            try:
                idx_st = idx_entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if stat.S_ISLNK(idx_st.st_mode):
                safe_remove_entry(idx_path, dry_run=dry_run)
                continue
            if not stat.S_ISDIR(idx_st.st_mode):
                continue
            try:
                pkg_entries = list(os.scandir(idx_path))
            except OSError:
                continue
            for pkg_entry in pkg_entries:
                pkg_path = Path(pkg_entry.path)
                try:
                    pkg_st = pkg_entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISLNK(pkg_st.st_mode):
                    safe_remove_entry(pkg_path, dry_run=dry_run)
                    continue
                if not stat.S_ISDIR(pkg_st.st_mode):
                    continue
                ref_mtime = _dir_reference_mtime(pkg_path, pkg_st.st_mtime)
                if max_age_days > 0 and (now - ref_mtime) > cutoff:
                    reclaimed += safe_remove_entry(pkg_path, dry_run=dry_run)
                    removed_trees += 1

    cache_root = cargo_home / "registry" / "cache"
    if max_bytes > 0 and _is_plain_dir(cache_root):
        crate_records: list[tuple[float, str, Path, int, str]] = []
        try:
            idx_entries = list(os.scandir(cache_root))
        except OSError:
            idx_entries = []
        for idx_entry in idx_entries:
            idx_path = Path(idx_entry.path)
            if not _is_plain_dir(idx_path):
                continue
            try:
                files = list(os.scandir(idx_path))
            except OSError:
                continue
            for f_entry in files:
                try:
                    f_st = f_entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISLNK(f_st.st_mode):
                    safe_remove_entry(Path(f_entry.path), dry_run=dry_run)
                    continue
                if stat.S_ISREG(f_st.st_mode) and f_entry.name.endswith(".crate"):
                    crate_records.append(
                        (
                            f_st.st_mtime,
                            f_entry.name,
                            Path(f_entry.path),
                            f_st.st_size,
                            idx_entry.name,
                        )
                    )
        total_crate_bytes = sum(item[3] for item in crate_records)
        if total_crate_bytes > max_bytes:
            low_watermark = int(max_bytes * 0.8)
            crate_records.sort(key=lambda item: (item[0], item[1]))
            for _, crate_name, crate_path, crate_size, idx_name in crate_records:
                if total_crate_bytes <= low_watermark:
                    break
                reclaimed += safe_remove_entry(crate_path, dry_run=dry_run)
                total_crate_bytes -= crate_size
                removed_crates += 1
                stem = crate_name.removesuffix(".crate")
                matching_src = cargo_home / "registry" / "src" / idx_name / stem
                if _is_plain_dir(matching_src):
                    reclaimed += safe_remove_entry(matching_src, dry_run=dry_run)
                    removed_trees += 1

    return {
        "present": True,
        "strategy": "cargo",
        "removedUnpackedTrees": removed_trees,
        "removedCrateArchives": removed_crates,
        "reclaimedBytes": reclaimed,
    }


def prune_npm_cache(
    npm_dir: Path,
    *,
    max_age_days: float,
    max_bytes: int,
    idle: bool,
    dry_run: bool,
    now: float,
) -> dict:
    if not _is_plain_dir(npm_dir):
        return {"present": False, "strategy": "npm", "reclaimedBytes": 0}
    reclaimed = prune_expired_files(
        npm_dir / "_logs", max_age_days=max_age_days, dry_run=dry_run, now=now
    )
    reset = False
    if idle and max_bytes > 0 and tree_bytes(npm_dir, dry_run=dry_run) > max_bytes:
        reclaimed += safe_clear_dir_contents(npm_dir, dry_run=dry_run)
        reset = True
    return {
        "present": True,
        "strategy": "npm",
        "quotaReset": reset,
        "reclaimedBytes": reclaimed,
    }


def prune_gradle_cache(
    gradle_dir: Path,
    *,
    max_age_days: float,
    max_bytes: int,
    idle: bool,
    dry_run: bool,
    now: float,
) -> dict:
    if not _is_plain_dir(gradle_dir):
        return {"present": False, "strategy": "gradle", "reclaimedBytes": 0}
    if not idle:
        return {
            "present": True,
            "strategy": "gradle",
            "skipped": "active_containers",
            "reclaimedBytes": 0,
        }

    reclaimed = 0
    daemon_root = gradle_dir / "daemon"
    cutoff = max_age_days * 86400.0
    if max_age_days > 0 and _is_plain_dir(daemon_root):
        try:
            ver_entries = list(os.scandir(daemon_root))
        except OSError:
            ver_entries = []
        for ver_entry in ver_entries:
            ver_path = Path(ver_entry.path)
            if ver_entry.is_symlink():
                safe_remove_entry(ver_path, dry_run=dry_run)
                continue
            if not _is_plain_dir(ver_path):
                continue
            try:
                log_entries = list(os.scandir(ver_path))
            except OSError:
                continue
            for log_entry in log_entries:
                log_path = Path(log_entry.path)
                try:
                    st = log_entry.stat(follow_symlinks=False)
                except OSError:
                    continue
                if stat.S_ISLNK(st.st_mode):
                    safe_remove_entry(log_path, dry_run=dry_run)
                elif (
                    stat.S_ISREG(st.st_mode)
                    and log_entry.name.endswith(".out.log")
                    and (now - st.st_mtime) > cutoff
                ):
                    reclaimed += safe_remove_entry(log_path, dry_run=dry_run)

    reset = False
    if max_bytes > 0 and tree_bytes(gradle_dir, dry_run=dry_run) > max_bytes:
        for sub_rel in GRADLE_RECLAIMABLE_SUBDIRS:
            sub_dir = gradle_dir / sub_rel
            if sub_dir.is_symlink():
                reclaimed += safe_remove_entry(sub_dir, dry_run=dry_run)
            elif _is_plain_dir(sub_dir):
                reclaimed += safe_clear_dir_contents(sub_dir, dry_run=dry_run)
        reset = True

    return {
        "present": True,
        "strategy": "gradle",
        "quotaReset": reset,
        "reclaimedBytes": reclaimed,
    }


def prune_idle_age_and_quota(
    pool_dir: Path,
    *,
    max_age_days: float,
    max_bytes: int,
    idle: bool,
    dry_run: bool,
    now: float,
) -> dict:
    if not _is_plain_dir(pool_dir):
        return {"present": False, "strategy": "idle-age-and-quota", "reclaimedBytes": 0}
    if not idle:
        return {
            "present": True,
            "strategy": "idle-age-and-quota",
            "skipped": "active_containers",
            "reclaimedBytes": 0,
        }
    reclaimed = prune_expired_files(
        pool_dir, max_age_days=max_age_days, dry_run=dry_run, now=now
    )
    reset = False
    if max_bytes > 0 and tree_bytes(pool_dir, dry_run=dry_run) > max_bytes:
        reclaimed += safe_clear_dir_contents(pool_dir, dry_run=dry_run)
        reset = True
    return {
        "present": True,
        "strategy": "idle-age-and-quota",
        "quotaReset": reset,
        "reclaimedBytes": reclaimed,
    }


def prune_idle_quota_reset(
    pool_dir: Path,
    *,
    max_bytes: int,
    idle: bool,
    dry_run: bool,
) -> dict:
    if not _is_plain_dir(pool_dir):
        return {"present": False, "strategy": "idle-quota-reset", "reclaimedBytes": 0}
    if not idle:
        return {
            "present": True,
            "strategy": "idle-quota-reset",
            "skipped": "active_containers",
            "reclaimedBytes": 0,
        }
    reclaimed = 0
    reset = False
    if max_bytes > 0 and tree_bytes(pool_dir, dry_run=dry_run) > max_bytes:
        reclaimed = safe_clear_dir_contents(pool_dir, dry_run=dry_run)
        reset = True
    return {
        "present": True,
        "strategy": "idle-quota-reset",
        "quotaReset": reset,
        "reclaimedBytes": reclaimed,
    }


def report_manual_pool(pool_dir: Path) -> dict:
    if not _is_plain_dir(pool_dir):
        return {
            "present": False,
            "strategy": "manual",
            "sizeBytes": 0,
            "reclaimedBytes": 0,
        }
    return {
        "present": True,
        "strategy": "manual",
        "sizeBytes": tree_bytes(pool_dir, dry_run=True),
        "reclaimedBytes": 0,
    }


def _parse_target_override(spec: str) -> tuple[str, Path]:
    if "=" not in spec:
        raise argparse.ArgumentTypeError(f"expected ID=PATH, got {spec!r}")
    mount_id, raw_path = spec.split("=", 1)
    if not MOUNT_ID_RE.match(mount_id) or not raw_path:
        raise argparse.ArgumentTypeError(f"invalid target override: {spec!r}")
    return mount_id, Path(raw_path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="devcontainer-runtime prune-caches",
        description="Reclaim expired and over-quota entries across shared caches declared in cache-layout.json.",
    )
    parser.add_argument("--cache-layout", type=Path, default=None)
    parser.add_argument(
        "--target-override",
        action="append",
        default=[],
        type=_parse_target_override,
        metavar="ID=PATH",
        help="Override target directory path for a specific cache pool ID",
    )
    parser.add_argument("--max-age-days", type=float, default=None)
    parser.add_argument("--nix-max-bytes", type=int, default=None)
    parser.add_argument("--pool-max-bytes", type=int, default=None)
    parser.add_argument("--grace-seconds", type=float, default=DEFAULT_GRACE_SECONDS)
    parser.add_argument(
        "--idle",
        action="store_true",
        help="Run deep reclamation assuming no active containers mount these caches",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report reclaimable bytes without modifying files",
    )
    return parser


def run_prune(
    *,
    cache_layout_path: Path | None = None,
    target_overrides: dict[str, Path] | None = None,
    max_age_days: float | None = None,
    nix_max_bytes: int | None = None,
    pool_max_bytes: int | None = None,
    grace_seconds: float = DEFAULT_GRACE_SECONDS,
    idle: bool = False,
    dry_run: bool = False,
    now: float | None = None,
    uv_bin: str | None | object = _AUTO_UV_BIN,
) -> dict:
    current = time.time() if now is None else now
    mounts = load_cache_layout(cache_layout_path)
    overrides = target_overrides or {}

    pools_report: dict[str, dict] = {}
    reset_pools: list[str] = []
    total_reclaimed = 0

    for item in mounts:
        mount_id = item["id"]
        target_dir = overrides.get(mount_id, Path(item["target"]))
        prune_spec = item["prune"]
        strategy = prune_spec["strategy"]

        default_age = float(prune_spec.get("maxAgeDays") or 30.0)
        entry_age = default_age if max_age_days is None else max_age_days

        raw_max_bytes = prune_spec.get("maxBytes")
        default_bytes = int(raw_max_bytes) if raw_max_bytes is not None else 0

        if strategy == "nix-tombstone":
            entry_max_bytes = default_bytes if nix_max_bytes is None else nix_max_bytes
            report = prune_nix_cache(
                target_dir,
                max_age_days=entry_age,
                max_bytes=entry_max_bytes,
                grace_seconds=grace_seconds,
                idle=idle,
                dry_run=dry_run,
                now=current,
            )
        elif strategy == "cargo":
            entry_max_bytes = (
                default_bytes if pool_max_bytes is None else pool_max_bytes
            )
            report = prune_cargo_cache(
                target_dir,
                max_age_days=entry_age,
                max_bytes=entry_max_bytes,
                idle=idle,
                dry_run=dry_run,
                now=current,
            )
        elif strategy == "uv":
            entry_max_bytes = (
                default_bytes if pool_max_bytes is None else pool_max_bytes
            )
            report = prune_uv_cache(
                target_dir,
                max_bytes=entry_max_bytes,
                idle=idle,
                dry_run=dry_run,
                uv_bin=uv_bin,
            )
        elif strategy == "npm":
            entry_max_bytes = (
                default_bytes if pool_max_bytes is None else pool_max_bytes
            )
            report = prune_npm_cache(
                target_dir,
                max_age_days=entry_age,
                max_bytes=entry_max_bytes,
                idle=idle,
                dry_run=dry_run,
                now=current,
            )
        elif strategy == "gradle":
            entry_max_bytes = (
                default_bytes if pool_max_bytes is None else pool_max_bytes
            )
            report = prune_gradle_cache(
                target_dir,
                max_age_days=entry_age,
                max_bytes=entry_max_bytes,
                idle=idle,
                dry_run=dry_run,
                now=current,
            )
        elif strategy == "idle-age-and-quota":
            entry_max_bytes = (
                default_bytes if pool_max_bytes is None else pool_max_bytes
            )
            report = prune_idle_age_and_quota(
                target_dir,
                max_age_days=entry_age,
                max_bytes=entry_max_bytes,
                idle=idle,
                dry_run=dry_run,
                now=current,
            )
        elif strategy == "idle-quota-reset":
            entry_max_bytes = (
                default_bytes if pool_max_bytes is None else pool_max_bytes
            )
            report = prune_idle_quota_reset(
                target_dir,
                max_bytes=entry_max_bytes,
                idle=idle,
                dry_run=dry_run,
            )
        elif strategy == "manual":
            report = report_manual_pool(target_dir)
        else:
            raise ValueError(f"Unhandled strategy {strategy!r} for {mount_id}")

        pools_report[mount_id] = report
        total_reclaimed += int(report.get("reclaimedBytes", 0))
        if report.get("quotaReset"):
            reset_pools.append(mount_id)

    return {
        "dryRun": dry_run,
        "idle": idle,
        "reclaimedBytes": total_reclaimed,
        "resetPools": sorted(reset_pools),
        "pools": pools_report,
    }


def run_cli(argv: list[str], environ: dict[str, str]) -> int:
    _ = environ
    args = build_parser().parse_args(argv)
    for val in (
        args.max_age_days,
        args.nix_max_bytes,
        args.pool_max_bytes,
        args.grace_seconds,
    ):
        if val is not None and val < 0:
            print(
                "devcontainer-runtime prune-caches: thresholds must be non-negative",
                file=sys.stderr,
            )
            return 2

    summary = run_prune(
        cache_layout_path=args.cache_layout,
        target_overrides=dict(args.target_override),
        max_age_days=args.max_age_days,
        nix_max_bytes=args.nix_max_bytes,
        pool_max_bytes=args.pool_max_bytes,
        grace_seconds=args.grace_seconds,
        idle=args.idle,
        dry_run=args.dry_run,
    )
    print(json.dumps(summary, sort_keys=True))
    return 0
