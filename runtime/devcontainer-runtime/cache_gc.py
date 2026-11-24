"""Symlink-safe online and idle garbage collection for shared Nix and language caches."""

import argparse
import json
import os
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

DEFAULT_MAX_AGE_DAYS = 30.0
DEFAULT_NIX_MAX_BYTES = 32 * 1024 * 1024 * 1024
DEFAULT_LANG_ARCHIVE_MAX_BYTES = 20 * 1024 * 1024 * 1024
DEFAULT_GRACE_SECONDS = 600.0


@dataclass(frozen=True)
class NarInfoEntry:
    path: Path
    store_hash: str
    nar_name: str
    mtime: float
    info_size: int


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


def tree_bytes(root: Path) -> int:
    if not _is_plain_dir(root):
        return 0
    total = 0
    stack = [root]
    while stack:
        current = stack.pop()
        try:
            entries = list(os.scandir(current))
        except PermissionError:
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
        return {"present": False, "reclaimedBytes": 0}

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

    if not idle and not dry_run:
        # Newly evicted entries in dry_run have not moved to staging yet; in online dry_run
        # grace window keeps their NARs protected until a subsequent pass after grace_seconds.
        pass
    elif not idle and dry_run:
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
        "evictedNarinfos": len(evicted),
        "tombstonedNarinfos": tombstoned_count,
        "removedNarinfos": unlinked_info_count + expired_tombstones,
        "removedNars": removed_nars,
        "removedStaleTemps": stale_tmp_count,
        "survivingNarinfos": len(surviving),
        "reclaimedBytes": reclaimed_bytes,
    }


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
    xdg_cache: Path,
    *,
    lang_archive_max_bytes: int,
    idle: bool,
    dry_run: bool,
) -> dict:
    uv_dir = xdg_cache / "uv"
    if not _is_plain_dir(uv_dir):
        return {"present": False, "reclaimedBytes": 0}
    before = tree_bytes(uv_dir)
    ran_uv_prune = False
    uv_bin = _find_uv_binary()
    if uv_bin and not dry_run:
        clean_env = {"PATH": "/usr/bin:/bin", "HOME": "/tmp", "UV_NO_CONFIG": "1"}
        res = subprocess.run(
            [
                uv_bin,
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

    after = tree_bytes(uv_dir)
    reclaimed = max(0, before - after)
    reset = False
    if idle and lang_archive_max_bytes > 0 and after > lang_archive_max_bytes:
        reclaimed += safe_clear_dir_contents(uv_dir, dry_run=dry_run)
        reset = True
    return {
        "present": True,
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
    lang_archive_max_bytes: int,
    idle: bool,
    dry_run: bool,
    now: float,
) -> dict:
    if not _is_plain_dir(cargo_home):
        return {"present": False, "reclaimedBytes": 0}
    if not idle:
        return {"present": True, "skipped": "active_containers", "reclaimedBytes": 0}

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
    if lang_archive_max_bytes > 0 and _is_plain_dir(cache_root):
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
        if total_crate_bytes > lang_archive_max_bytes:
            low_watermark = int(lang_archive_max_bytes * 0.8)
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
        "removedUnpackedTrees": removed_trees,
        "removedCrateArchives": removed_crates,
        "reclaimedBytes": reclaimed,
    }


def prune_archive_pools(
    xdg_cache: Path,
    *,
    lang_archive_max_bytes: int,
    idle: bool,
    dry_run: bool,
) -> dict:
    pools = {
        "gomodcache": xdg_cache / "go" / "pkg" / "mod",
        "gobuild": xdg_cache / "go-build",
        "pnpm": xdg_cache / "pnpm" / "store",
        "npm": xdg_cache / "npm",
        "yarn": xdg_cache / "yarn",
        "pip": xdg_cache / "pip",
        "corepack": xdg_cache / "corepack",
    }
    if not idle or lang_archive_max_bytes <= 0:
        return {"resetPools": [], "reclaimedBytes": 0}

    reset_pools: list[str] = []
    reclaimed = 0
    for name, pool_dir in pools.items():
        if not _is_plain_dir(pool_dir):
            continue
        size = tree_bytes(pool_dir)
        if size > lang_archive_max_bytes:
            reclaimed += safe_clear_dir_contents(pool_dir, dry_run=dry_run)
            reset_pools.append(name)
    return {"resetPools": reset_pools, "reclaimedBytes": reclaimed}


def build_parser(environ: dict[str, str]) -> argparse.ArgumentParser:
    home = environ.get("HOME") or "/home/vscode"
    default_xdg = environ.get("XDG_CACHE_HOME") or str(Path(home) / ".cache")
    default_cargo = environ.get("CARGO_HOME") or str(
        Path(home) / ".local" / "share" / "cargo"
    )
    default_nix = environ.get(
        "DEVCONTAINER_SHARED_NIX_CACHE_DIR", state.DEFAULT_SHARED_NIX_CACHE_DIR
    )

    parser = argparse.ArgumentParser(
        prog="devcontainer-runtime prune-caches",
        description="Reclaim expired and over-quota entries in shared container caches.",
    )
    parser.add_argument("--nix-cache-dir", type=Path, default=Path(default_nix))
    parser.add_argument("--xdg-cache-dir", type=Path, default=Path(default_xdg))
    parser.add_argument("--cargo-home", type=Path, default=Path(default_cargo))
    parser.add_argument("--max-age-days", type=float, default=DEFAULT_MAX_AGE_DAYS)
    parser.add_argument("--nix-max-bytes", type=int, default=DEFAULT_NIX_MAX_BYTES)
    parser.add_argument(
        "--lang-archive-max-bytes", type=int, default=DEFAULT_LANG_ARCHIVE_MAX_BYTES
    )
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
    nix_cache_dir: Path,
    xdg_cache_dir: Path,
    cargo_home: Path,
    max_age_days: float,
    nix_max_bytes: int,
    lang_archive_max_bytes: int,
    grace_seconds: float,
    idle: bool,
    dry_run: bool,
    now: float | None = None,
) -> dict:
    current = time.time() if now is None else now
    nix_report = prune_nix_cache(
        nix_cache_dir,
        max_age_days=max_age_days,
        max_bytes=nix_max_bytes,
        grace_seconds=grace_seconds,
        idle=idle,
        dry_run=dry_run,
        now=current,
    )
    uv_report = prune_uv_cache(
        xdg_cache_dir,
        lang_archive_max_bytes=lang_archive_max_bytes,
        idle=idle,
        dry_run=dry_run,
    )
    py_bytes = 0
    if _is_plain_dir(xdg_cache_dir):
        py_bytes += prune_expired_files(
            xdg_cache_dir / "python",
            max_age_days=max_age_days,
            dry_run=dry_run,
            now=current,
        )
        py_bytes += prune_expired_files(
            xdg_cache_dir / "mypy",
            max_age_days=max_age_days,
            dry_run=dry_run,
            now=current,
        )
    cargo_report = prune_cargo_cache(
        cargo_home,
        max_age_days=max_age_days,
        lang_archive_max_bytes=lang_archive_max_bytes,
        idle=idle,
        dry_run=dry_run,
        now=current,
    )
    archives_report = prune_archive_pools(
        xdg_cache_dir,
        lang_archive_max_bytes=lang_archive_max_bytes,
        idle=idle,
        dry_run=dry_run,
    )

    total_reclaimed = (
        nix_report["reclaimedBytes"]
        + uv_report["reclaimedBytes"]
        + py_bytes
        + cargo_report["reclaimedBytes"]
        + archives_report["reclaimedBytes"]
    )
    return {
        "dryRun": dry_run,
        "idle": idle,
        "reclaimedBytes": total_reclaimed,
        "nix": nix_report,
        "uv": uv_report,
        "pythonBytecode": {"reclaimedBytes": py_bytes},
        "cargo": cargo_report,
        "archives": archives_report,
    }


def run_cli(argv: list[str], environ: dict[str, str]) -> int:
    args = build_parser(environ).parse_args(argv)
    if (
        args.max_age_days < 0
        or args.nix_max_bytes < 0
        or args.lang_archive_max_bytes < 0
        or args.grace_seconds < 0
    ):
        print(
            "devcontainer-runtime prune-caches: thresholds must be non-negative",
            file=sys.stderr,
        )
        return 2
    summary = run_prune(
        nix_cache_dir=args.nix_cache_dir,
        xdg_cache_dir=args.xdg_cache_dir,
        cargo_home=args.cargo_home,
        max_age_days=args.max_age_days,
        nix_max_bytes=args.nix_max_bytes,
        lang_archive_max_bytes=args.lang_archive_max_bytes,
        grace_seconds=args.grace_seconds,
        idle=args.idle,
        dry_run=args.dry_run,
    )
    print(json.dumps(summary, sort_keys=True))
    return 0
