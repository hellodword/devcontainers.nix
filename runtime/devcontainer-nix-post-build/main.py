#!/usr/bin/env python3
"""Lock-free single-path Nix binary cache publisher invoked via post-build-hook."""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "@runtimeLibrary@")
import devcontainer_state as state

NIX_BIN = "@nix@"
ZSTD_BIN = "@zstd@"

STORE_HASH_RE = re.compile(r"^[0-9a-df-np-sv-z]{32}$")
ATERM_NO_SUBST_RE = re.compile(r'\("allowSubstitutes","(?:|0|false)"\)')
CHUNK_BYTES = 262144


def debug_enabled(environ: dict[str, str]) -> bool:
    return environ.get("DEVCONTAINER_NIX_CACHE_DEBUG", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def drv_disables_substitutes(drv_path_str: str) -> bool:
    if not drv_path_str:
        return False
    drv_path = Path(drv_path_str)
    try:
        if not drv_path.is_file():
            return False
        with drv_path.open("r", encoding="utf-8", errors="replace") as handle:
            text = handle.read(524288)
    except OSError:
        return False

    return bool(
        ATERM_NO_SUBST_RE.search(text)
        or ('"__json","' in text and '\\"allowSubstitutes\\":false' in text)
    )


def resolve_cache_dir(cache_dir_override: Path | None = None) -> Path | None:
    raw_dir = cache_dir_override or state.DEFAULT_SHARED_NIX_CACHE_DIR
    cache_dir = state.validate_shared_cache_path(raw_dir)
    if not cache_dir.exists() or cache_dir.is_symlink() or not cache_dir.is_dir():
        return None
    if not os.access(cache_dir, os.W_OK | os.X_OK):
        return None
    return cache_dir


def store_hash_of(store_path: str) -> str | None:
    if not store_path.startswith("/nix/store/"):
        return None
    name = store_path.removeprefix("/nix/store/")
    if "/" in name or "-" not in name:
        return None
    prefix = name.split("-", 1)[0]
    if not STORE_HASH_RE.fullmatch(prefix):
        return None
    return prefix


def query_path_info(paths: list[str], environ: dict[str, str]) -> dict[str, dict]:
    clean_env = dict(environ)
    clean_env["NIX_PAGER"] = "cat"
    proc = subprocess.run(
        [
            NIX_BIN,
            "--extra-experimental-features",
            "nix-command",
            "path-info",
            "--json",
            "--json-format",
            "1",
            "--stdin",
        ],
        input="".join(f"{p}\n" for p in paths),
        capture_output=True,
        text=True,
        env=clean_env,
        check=True,
    )
    parsed = json.loads(proc.stdout or "{}")
    if not isinstance(parsed, dict):
        raise TypeError("unexpected JSON payload from nix path-info")
    return parsed


def format_narinfo(
    store_path: str,
    *,
    file_nix32: str,
    file_size: int,
    nar_hash: str,
    nar_size: int,
    references: list[str],
    deriver: str | None,
    ca: str | None,
) -> bytes:
    ref_names = sorted(Path(ref).name for ref in references if ref)
    lines = [
        f"StorePath: {store_path}",
        f"URL: nar/{file_nix32}.nar.zst",
        "Compression: zstd",
        f"FileHash: sha256:{file_nix32}",
        f"FileSize: {file_size}",
        f"NarHash: {nar_hash}",
        f"NarSize: {nar_size}",
        f"References: {' '.join(ref_names)}",
    ]
    if deriver:
        lines.append(f"Deriver: {Path(deriver).name}")
    if ca:
        lines.append(f"CA: {ca}")
    return ("\n".join(lines) + "\n").encode("ascii")


def dump_and_compress_nar(
    store_path: str, staging_dir: Path, environ: dict[str, str]
) -> tuple[Path, str, int]:
    fd, tmp_nar = state.create_staging_temp(staging_dir, "nar", 0o644)
    clean_env = dict(environ)
    clean_env["NIX_PAGER"] = "cat"
    dump_proc: subprocess.Popen | None = None
    zstd_proc: subprocess.Popen | None = None
    try:
        dump_proc = subprocess.Popen(
            [
                NIX_BIN,
                "--extra-experimental-features",
                "nix-command",
                "store",
                "dump-path",
                "--",
                store_path,
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=clean_env,
        )
        assert dump_proc.stdout is not None
        zstd_proc = subprocess.Popen(
            [ZSTD_BIN, "-T0", "-3", "-q", "-c"],
            stdin=dump_proc.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        dump_proc.stdout.close()
        assert zstd_proc.stdout is not None

        hasher = hashlib.sha256()
        file_size = 0
        with os.fdopen(fd, "wb") as out_handle:
            fd = -1
            while True:
                chunk = zstd_proc.stdout.read(CHUNK_BYTES)
                if not chunk:
                    break
                hasher.update(chunk)
                file_size += len(chunk)
                out_handle.write(chunk)
            out_handle.flush()
            os.fsync(out_handle.fileno())

        _, zstd_err = zstd_proc.communicate()
        _, dump_err = dump_proc.communicate()
        if dump_proc.returncode != 0:
            raise RuntimeError(
                f"nix store dump-path failed ({dump_proc.returncode}): {dump_err.decode('utf-8', 'replace').strip()}"
            )
        if zstd_proc.returncode != 0:
            raise RuntimeError(
                f"zstd failed ({zstd_proc.returncode}): {zstd_err.decode('utf-8', 'replace').strip()}"
            )
        if file_size <= 0:
            raise RuntimeError(f"empty compressed NAR stream for {store_path}")
        return tmp_nar, state.to_nix32_sha256(hasher.digest()), file_size
    except BaseException:
        if fd >= 0:
            os.close(fd)
        if zstd_proc is not None and zstd_proc.poll() is None:
            zstd_proc.kill()
            zstd_proc.wait()
        if dump_proc is not None and dump_proc.poll() is None:
            dump_proc.kill()
            dump_proc.wait()
        tmp_nar.unlink(missing_ok=True)
        raise


def publish_outputs(
    environ: dict[str, str], *, cache_dir_override: Path | None = None
) -> int:
    raw_out = environ.get("OUT_PATHS", "").strip()
    if not raw_out:
        return 0
    if drv_disables_substitutes(environ.get("DRV_PATH", "")):
        return 0

    cache_dir = resolve_cache_dir(cache_dir_override)
    if cache_dir is None:
        return 0

    pending: list[tuple[str, str]] = []
    for candidate in raw_out.split():
        store_hash = store_hash_of(candidate)
        if store_hash is None:
            continue
        if (cache_dir / f"{store_hash}.narinfo").is_file():
            continue
        pending.append((candidate, store_hash))
    if not pending:
        return 0

    nar_dir = cache_dir / "nar"
    staging_dir = cache_dir / ".staging"
    for directory in (
        *(cache_dir / sub for sub in state.SHARED_CACHE_SUBDIRS),
        staging_dir,
    ):
        directory.mkdir(mode=0o755, exist_ok=True)
        if directory.is_symlink() or not directory.is_dir():
            return 0
    if not (cache_dir / "nix-cache-info").is_file():
        state.publish_immutable_bytes(
            cache_dir,
            staging_dir,
            Path("nix-cache-info"),
            state.NIX_CACHE_INFO_TEXT.encode("ascii"),
        )

    infos = query_path_info([item[0] for item in pending], environ)

    staged_narinfos: list[tuple[str, bytes]] = []
    for store_path, store_hash in pending:
        if (cache_dir / f"{store_hash}.narinfo").is_file():
            continue
        info = infos.get(store_path)
        if not isinstance(info, dict):
            continue
        nar_size = info.get("narSize")
        if not isinstance(nar_size, int) or nar_size < 0:
            continue
        nar_hash = state.normalize_sri_or_nix32_sha256(str(info.get("narHash") or ""))
        tmp_nar, file_nix32, file_size = dump_and_compress_nar(
            store_path, staging_dir, environ
        )
        state.publish_immutable_file(tmp_nar, nar_dir / f"{file_nix32}.nar.zst")
        narinfo_payload = format_narinfo(
            store_path,
            file_nix32=file_nix32,
            file_size=file_size,
            nar_hash=nar_hash,
            nar_size=nar_size,
            references=list(info.get("references") or []),
            deriver=info.get("deriver"),
            ca=info.get("ca"),
        )
        staged_narinfos.append((store_hash, narinfo_payload))

    if not staged_narinfos:
        return 0

    state.fsync_dir(nar_dir)
    published_any = False
    for store_hash, payload in staged_narinfos:
        if state.publish_immutable_bytes(
            cache_dir, staging_dir, Path(f"{store_hash}.narinfo"), payload
        ):
            published_any = True
    if published_any:
        state.fsync_dir(cache_dir)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=None,
        help="Target shared file:// cache directory (defaults to /var/cache/devcontainer-nix)",
    )
    args = parser.parse_args(argv)
    try:
        return publish_outputs(os.environ, cache_dir_override=args.cache_dir)
    except (
        state.StateError,
        OSError,
        RuntimeError,
        subprocess.SubprocessError,
        TypeError,
        ValueError,
    ) as exc:
        if debug_enabled(os.environ):
            print(f"devcontainer-nix-post-build: {exc}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
