#!/usr/bin/env python3
"""Offline contract, concurrency, and symlink-isolation tests for runtime cache discovery, publishing, and pruning."""

from __future__ import annotations

import argparse
import http.server
import json
import os
import socketserver
import stat
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "runtime" / "devcontainer-runtime"))

import cache_gc
import state


class _QuietHandler(http.server.BaseHTTPRequestHandler):
    body_bytes = b""
    status_code = 200

    def do_GET(self) -> None:
        if self.path == "/nix-cache-info":
            self.send_response(self.status_code)
            self.send_header("Content-Type", "text/x-nix-cache-info")
            self.send_header("Content-Length", str(len(self.body_bytes)))
            self.end_headers()
            self.wfile.write(self.body_bytes)
            return
        self.send_response(404)
        self.end_headers()

    def log_message(self, format: str, *args) -> None:
        return


class _ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


def _serve_http(body: bytes, status_code: int = 200):
    class Handler(_QuietHandler):
        pass

    Handler.body_bytes = body
    Handler.status_code = status_code
    server = _ReusableTCPServer(("127.0.0.1", 0), Handler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"127.0.0.1:{port}"


def _run_post_build_worker(args: tuple[str, str, str, str]) -> int:
    post_build_hook, cache_dir, out_path, drv_path = args
    env = dict(os.environ)
    env["DEVCONTAINER_SHARED_NIX_CACHE_DIR"] = cache_dir
    env["DEVCONTAINER_NIX_CACHE_DEBUG"] = "1"
    env["OUT_PATHS"] = out_path
    if drv_path:
        env["DRV_PATH"] = drv_path
    else:
        env.pop("DRV_PATH", None)
    res = subprocess.run(
        [post_build_hook],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0 or res.stderr.strip():
        raise AssertionError(
            f"post-build worker failed (rc={res.returncode}): {res.stderr}"
        )
    return res.returncode


def test_discovery_and_probes(work_dir: Path) -> None:
    home = work_dir / "home"
    state_home = home / ".local" / "state"
    conf_file = state_home / "devcontainer" / "nix-local-cache.conf"
    hook_path = "/nix/store/mock-hook/bin/devcontainer-nix-post-build"

    base_env = {
        "HOME": str(home),
        "XDG_STATE_HOME": str(state_home),
        "DEVCONTAINER_LOCAL_CACHE_ADDR": "127.0.0.1:1",
        "DEVCONTAINER_HOST_STORE_CACHE_ADDR": "127.0.0.1:1",
    }

    # 1. Unmounted cache dir and closed ports -> no config file written.
    unmounted_cache = work_dir / "unmounted-nix-cache"
    unmounted_cache.mkdir(parents=True)
    env = {
        **base_env,
        "DEVCONTAINER_SHARED_NIX_CACHE": "auto",
        "DEVCONTAINER_SHARED_NIX_CACHE_DIR": str(unmounted_cache),
    }
    assert not state.refresh_local_cache(env, mounts=set(), post_build_hook=hook_path)
    assert not conf_file.exists()

    # 2. Writable mounted shared cache initializes structure, sweeps stale .tmp, and wires hook.
    rw_cache = work_dir / "rw-nix-cache"
    (rw_cache / ".staging").mkdir(parents=True)
    stale_tmp = rw_cache / ".staging" / "nar-deadbeef.tmp"
    stale_tmp.write_bytes(b"partial")
    old_ts = time.time() - (state.STAGING_MAX_AGE_SECONDS + 120)
    os.utime(stale_tmp, (old_ts, old_ts))

    env_rw = {
        **base_env,
        "DEVCONTAINER_SHARED_NIX_CACHE": "auto",
        "DEVCONTAINER_SHARED_NIX_CACHE_DIR": str(rw_cache),
    }
    assert state.refresh_local_cache(
        env_rw, mounts={rw_cache}, post_build_hook=hook_path, has_external_net=True
    )
    assert (rw_cache / "nix-cache-info").is_file()
    for sub in state.SHARED_CACHE_SUBDIRS:
        assert (rw_cache / sub).is_dir(), sub
    assert not stale_tmp.exists(), "Expected stale .staging/*.tmp to be swept"
    conf_text = conf_file.read_text(encoding="utf-8")
    assert (
        f"extra-substituters = file://{rw_cache}?trusted=1&priority=10" in conf_text
    ), conf_text
    assert f"post-build-hook = {hook_path}" in conf_text, conf_text

    assert state.refresh_local_cache(
        env_rw, mounts={rw_cache}, post_build_hook=hook_path, has_external_net=False
    )
    isolated_conf = conf_file.read_text(encoding="utf-8")
    assert isolated_conf.startswith(
        f"substituters = file://{rw_cache}?trusted=1&priority=10\n"
    ), isolated_conf

    # 3. Read-only mount: incomplete directory is skipped; initialized directory enables read-only substituter without hook.
    ro_incomplete = work_dir / "ro-incomplete"
    ro_incomplete.mkdir()
    os.chmod(ro_incomplete, 0o555)
    try:
        env_ro_bad = {
            **base_env,
            "DEVCONTAINER_SHARED_NIX_CACHE_DIR": str(ro_incomplete),
        }
        assert not state.refresh_local_cache(
            env_ro_bad, mounts={ro_incomplete}, post_build_hook=hook_path
        )
        assert not conf_file.exists()
    finally:
        os.chmod(ro_incomplete, 0o755)

    os.chmod(rw_cache, 0o555)
    try:
        assert state.refresh_local_cache(
            env_rw, mounts={rw_cache}, post_build_hook=hook_path
        )
        ro_conf = conf_file.read_text(encoding="utf-8")
        assert f"file://{rw_cache}?trusted=1&priority=10" in ro_conf, ro_conf
        assert "post-build-hook" not in ro_conf, ro_conf
    finally:
        os.chmod(rw_cache, 0o755)

    # 4. Port 37516 /nix-cache-info probe rejects generic HTTP 200 HTML server and accepts valid StoreDir response.
    fake_srv, fake_addr = _serve_http(b"<html>not a nix cache</html>\n")
    valid_srv, valid_addr = _serve_http(
        b"StoreDir: /nix/store\nWantMassQuery: 1\nPriority: 30\n"
    )
    oranc_srv, oranc_addr = _serve_http(b"ok\n")
    try:
        env_fake = {
            **base_env,
            "DEVCONTAINER_SHARED_NIX_CACHE": "0",
            "DEVCONTAINER_HOST_STORE_CACHE_ADDR": fake_addr,
        }
        assert not state.refresh_local_cache(
            env_fake, mounts=set(), post_build_hook=hook_path
        )

        env_both = {
            **base_env,
            "DEVCONTAINER_SHARED_NIX_CACHE": "auto",
            "DEVCONTAINER_SHARED_NIX_CACHE_DIR": str(rw_cache),
            "DEVCONTAINER_HOST_STORE_CACHE_ADDR": valid_addr,
            "DEVCONTAINER_LOCAL_CACHE_ADDR": oranc_addr,
        }
        assert state.refresh_local_cache(
            env_both, mounts={rw_cache}, post_build_hook=hook_path
        )
        combined = conf_file.read_text(encoding="utf-8")
        expected_order = (
            f"extra-substituters = file://{rw_cache}?trusted=1&priority=10 "
            f"http://{valid_addr}?trusted=1&priority=20 "
            f"http://{oranc_addr}/ghcr.io/hellodword/nixos-config-cache "
            f"http://{oranc_addr}/ghcr.io/hellodword/devcontainers-nix-cache"
        )
        assert expected_order in combined, combined
    finally:
        fake_srv.shutdown()
        valid_srv.shutdown()
        oranc_srv.shutdown()


def test_concurrent_single_path_publish(
    work_dir: Path,
    *,
    post_build_hook: Path,
    nix_bin: Path,
    sample_store_path: Path,
) -> None:
    resolved_sample = sample_store_path.resolve()
    assert str(resolved_sample).startswith("/nix/store/"), resolved_sample
    store_root = "/" + "/".join(resolved_sample.parts[1:4])
    store_hash = Path(store_root).name.split("-", 1)[0]

    cache_dir = work_dir / "concurrent-nix-cache"
    cache_dir.mkdir(parents=True)
    hook_str = str(post_build_hook)

    # Filtering check: allowSubstitutes = false derivation must be skipped.
    no_subst_drv = work_dir / "local-only.drv"
    no_subst_drv.write_text(
        'Derive([("out","/nix/store/00000000000000000000000000000000-x","","")],[],[],'
        '"x86_64-linux","/bin/sh",[],[("allowSubstitutes",""),("name","x")])',
        encoding="utf-8",
    )
    _run_post_build_worker((hook_str, str(cache_dir), store_root, str(no_subst_drv)))
    assert not (cache_dir / f"{store_hash}.narinfo").exists()

    # Filtering check: explicit DEVCONTAINER_SHARED_NIX_CACHE_MAX_NAR_BYTES cap skips larger output.
    cap_env = dict(os.environ)
    cap_env["DEVCONTAINER_SHARED_NIX_CACHE_DIR"] = str(cache_dir)
    cap_env["DEVCONTAINER_SHARED_NIX_CACHE_MAX_NAR_BYTES"] = "8"
    cap_env["OUT_PATHS"] = store_root
    res_cap = subprocess.run([hook_str], env=cap_env, check=True)
    assert res_cap.returncode == 0
    assert not (cache_dir / f"{store_hash}.narinfo").exists()

    # 8 concurrent processes publishing the same glibc-referencing store path into an empty cache.
    tasks = [(hook_str, str(cache_dir), store_root, "") for _ in range(8)]
    with ProcessPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(_run_post_build_worker, tasks))
    assert results == [0] * 8

    narinfo_path = cache_dir / f"{store_hash}.narinfo"
    assert narinfo_path.is_file()
    assert os.lstat(narinfo_path).st_nlink == 1
    assert list((cache_dir / ".staging").glob("*.tmp")) == []

    nar_files = list((cache_dir / "nar").glob("*.nar.zst"))
    assert len(nar_files) == 1
    assert os.lstat(nar_files[0]).st_nlink == 1

    # Verify Nix itself parses and validates the published entry in a read-only file:// store.
    xdg_cache = work_dir / "nix-client-cache"
    xdg_cache.mkdir(parents=True, exist_ok=True)
    verify_env = os.environ | {"XDG_CACHE_HOME": str(xdg_cache)}
    ro_dirs = [cache_dir, *(cache_dir / sub for sub in state.SHARED_CACHE_SUBDIRS)]
    for d in ro_dirs:
        os.chmod(d, 0o555)
    try:
        info_out = subprocess.check_output(
            [
                str(nix_bin),
                "--extra-experimental-features",
                "nix-command",
                "path-info",
                "--store",
                f"file://{cache_dir}",
                "--json",
                "--json-format",
                "1",
                store_root,
            ],
            env=verify_env,
            text=True,
            stderr=subprocess.PIPE,
        )
    finally:
        for d in ro_dirs:
            os.chmod(d, 0o755)
    parsed = json.loads(info_out)
    assert store_root in parsed, parsed
    assert parsed[store_root]["narSize"] > 0


def test_prune_caches_and_symlink_safety(work_dir: Path) -> None:
    layout_path = REPO_ROOT / "data" / "cache-layout.json"
    mounts = cache_gc.load_cache_layout(layout_path)
    assert len(mounts) == 20

    sentinel_dir = work_dir / "host-sentinel"
    sentinel_dir.mkdir(parents=True, exist_ok=True)
    sentinel_file = sentinel_dir / "secret.key"
    sentinel_file.write_text("DO_NOT_TOUCH\n", encoding="utf-8")
    os.chmod(sentinel_file, 0o600)

    pools_root = work_dir / "pools"
    overrides = {item["id"]: pools_root / item["id"] for item in mounts}

    nix_cache = overrides["nix"]
    (nix_cache / "nar").mkdir(parents=True)
    (nix_cache / "realisations").mkdir()
    (nix_cache / "log").mkdir()
    (nix_cache / ".staging").mkdir()
    (nix_cache / "nix-cache-info").write_text(
        state.NIX_CACHE_INFO_TEXT, encoding="utf-8"
    )

    now = time.time()
    old_mtime = now - 45 * 86400.0
    recent_mtime = now - 2 * 86400.0

    shared_nar = nix_cache / "nar" / ("a" * 52 + ".nar.zst")
    orphan_nar = nix_cache / "nar" / ("b" * 52 + ".nar.zst")
    fresh_writer_nar = nix_cache / "nar" / ("c" * 52 + ".nar.zst")
    for nar in (shared_nar, orphan_nar):
        nar.write_bytes(b"x" * 4096)
        os.utime(nar, (old_mtime, old_mtime))
    fresh_writer_nar.write_bytes(b"x" * 4096)
    os.utime(fresh_writer_nar, (now + 500.0, now + 500.0))

    os.symlink(sentinel_file, nix_cache / "nar" / "evil-link.nar.zst")

    old_shared_info = nix_cache / ("1" * 32 + ".narinfo")
    new_shared_info = nix_cache / ("2" * 32 + ".narinfo")
    old_orphan_info = nix_cache / ("3" * 32 + ".narinfo")

    old_shared_info.write_text(
        f"StorePath: /nix/store/{'1' * 32}-old\nURL: nar/{shared_nar.name}\n",
        encoding="utf-8",
    )
    new_shared_info.write_text(
        f"StorePath: /nix/store/{'2' * 32}-new\nURL: nar/{shared_nar.name}\n",
        encoding="utf-8",
    )
    old_orphan_info.write_text(
        f"StorePath: /nix/store/{'3' * 32}-orphan\nURL: nar/{orphan_nar.name}\n",
        encoding="utf-8",
    )
    os.utime(old_shared_info, (old_mtime, old_mtime))
    os.utime(new_shared_info, (recent_mtime, recent_mtime))
    os.utime(old_orphan_info, (old_mtime, old_mtime))

    gomod_ro = overrides["go-mod"] / "example.com" / "pkg@v1.0.0"
    gomod_ro.mkdir(parents=True)
    (gomod_ro / "mod.go").write_bytes(b"g" * 8192)
    os.symlink(sentinel_dir, gomod_ro / "escape-dir")
    os.chmod(gomod_ro, 0o555)

    cargo_home = overrides["cargo"]
    old_crate_src = cargo_home / "registry" / "src" / "index-1" / "serde-1.0.0"
    new_crate_src = cargo_home / "registry" / "src" / "index-1" / "tokio-1.0.0"
    old_crate_src.mkdir(parents=True)
    new_crate_src.mkdir(parents=True)
    (old_crate_src / ".cargo-ok").write_text("", encoding="utf-8")
    (old_crate_src / "lib.rs").write_bytes(b"r" * 2048)
    (new_crate_src / ".cargo-ok").write_text("", encoding="utf-8")
    os.symlink(sentinel_file, old_crate_src / "sentinel-link")
    os.utime(old_crate_src / ".cargo-ok", (old_mtime, old_mtime))
    os.utime(old_crate_src, (old_mtime, old_mtime))
    os.utime(new_crate_src / ".cargo-ok", (recent_mtime, recent_mtime))
    os.utime(new_crate_src, (recent_mtime, recent_mtime))

    pip_old = overrides["pip"] / "http-v2" / "old.whl"
    pip_new = overrides["pip"] / "http-v2" / "new.whl"
    pip_old.parent.mkdir(parents=True)
    pip_old.write_bytes(b"p" * 512)
    pip_new.write_bytes(b"p" * 256)
    os.utime(pip_old, (old_mtime, old_mtime))
    os.utime(pip_new, (recent_mtime, recent_mtime))

    gradle_old_log = overrides["gradle"] / "daemon" / "8.10" / "daemon-1.out.log"
    gradle_keep = overrides["gradle"] / "caches" / "modules-2" / "keep.jar"
    gradle_old_log.parent.mkdir(parents=True)
    gradle_keep.parent.mkdir(parents=True)
    gradle_old_log.write_bytes(b"l" * 512)
    gradle_keep.write_bytes(b"j" * 256)
    os.utime(gradle_old_log, (old_mtime, old_mtime))
    os.utime(gradle_keep, (old_mtime, old_mtime))

    chromium_pack = (
        overrides["chromium-git"]
        / "chromium.googlesource.com-chromium-src"
        / "objects"
        / "pack"
        / "pack-1.pack"
    )
    chromium_pack.parent.mkdir(parents=True)
    chromium_pack.write_bytes(b"c" * 16384)
    os.utime(chromium_pack, (old_mtime, old_mtime))

    # Pass 1 (online mode): old narinfos move to tombstones; orphan_nar stays alive during grace window;
    # idle-only pools and manual chromium-git remain untouched.
    online_res = cache_gc.run_prune(
        cache_layout_path=layout_path,
        target_overrides=overrides,
        max_age_days=30.0,
        nix_max_bytes=0,
        pool_max_bytes=1024,
        grace_seconds=600.0,
        idle=False,
        dry_run=False,
        now=now,
        uv_bin=None,
    )
    assert online_res["pools"]["nix"]["tombstonedNarinfos"] == 2, online_res
    assert not old_orphan_info.exists()
    assert orphan_nar.exists()
    assert shared_nar.exists()
    assert old_crate_src.exists()
    assert gomod_ro.exists()
    assert pip_old.exists()
    assert gradle_old_log.exists()
    assert chromium_pack.exists()
    assert online_res["pools"]["chromium-git"]["sizeBytes"] == 16384

    # Pass 2 (online mode after grace window): expired tombstones and orphan_nar are reclaimed;
    # shared_nar and fresh_writer_nar survive.
    online_after_grace = cache_gc.run_prune(
        cache_layout_path=layout_path,
        target_overrides=overrides,
        max_age_days=30.0,
        nix_max_bytes=0,
        pool_max_bytes=1024,
        grace_seconds=600.0,
        idle=False,
        dry_run=False,
        now=now + 601.0,
        uv_bin=None,
    )
    assert online_after_grace["pools"]["nix"]["removedNars"] == 1, online_after_grace
    assert not orphan_nar.exists()
    assert shared_nar.exists()
    assert fresh_writer_nar.exists()

    # Pass 3 (idle mode): sweeps unreferenced fresh_writer_nar, removes expired Cargo src, pip wheel,
    # and Gradle daemon log, resets over-quota 0555 GOMODCACHE, preserves manual chromium-git pack,
    # and leaves external sentinel_dir/sentinel_file untouched.
    idle_res = cache_gc.run_prune(
        cache_layout_path=layout_path,
        target_overrides=overrides,
        max_age_days=30.0,
        nix_max_bytes=0,
        pool_max_bytes=1024,
        grace_seconds=600.0,
        idle=True,
        dry_run=False,
        now=now + 602.0,
        uv_bin=None,
    )
    assert not fresh_writer_nar.exists()
    assert shared_nar.exists()
    assert not old_crate_src.exists()
    assert new_crate_src.exists()
    assert "go-mod" in idle_res["resetPools"], idle_res
    assert not gomod_ro.exists()
    assert not pip_old.exists()
    assert pip_new.exists()
    assert not gradle_old_log.exists()
    assert gradle_keep.exists()
    assert chromium_pack.exists(), (
        "Manual chromium-git bare pack must not be auto-deleted"
    )
    assert idle_res["pools"]["chromium-git"]["sizeBytes"] == 16384

    assert sentinel_file.read_text(encoding="utf-8") == "DO_NOT_TOUCH\n"
    assert stat.S_IMODE(os.lstat(sentinel_file).st_mode) == 0o600


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--post-build-hook",
        type=Path,
        default=os.environ.get("DEVCONTAINERS_POST_BUILD_HOOK"),
        help="Path to the built devcontainer-nix-post-build executable",
    )
    parser.add_argument(
        "--nix-bin",
        type=Path,
        default=os.environ.get("DEVCONTAINERS_NIX_BIN"),
        help="Path to the nix CLI executable",
    )
    parser.add_argument(
        "--sample-store-path",
        type=Path,
        default=os.environ.get("DEVCONTAINERS_SAMPLE_STORE_PATH"),
        help="Path inside /nix/store used to exercise single-path binary cache publication",
    )
    args = parser.parse_args(argv)
    missing = [
        flag
        for flag, val in (
            ("--post-build-hook", args.post_build_hook),
            ("--nix-bin", args.nix_bin),
            ("--sample-store-path", args.sample_store_path),
        )
        if val is None
    ]
    if missing:
        parser.error(f"missing required store-bound paths: {', '.join(missing)}")
    for flag, path in (
        ("--post-build-hook", args.post_build_hook),
        ("--nix-bin", args.nix_bin),
    ):
        if not path.is_file() or not os.access(path, os.X_OK):
            parser.error(f"{flag} is not an executable file: {path}")
    if not args.sample_store_path.exists():
        parser.error(f"--sample-store-path does not exist: {args.sample_store_path}")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    with tempfile.TemporaryDirectory(prefix="devcontainers-runtime-cache-") as tmp:
        work_dir = Path(tmp)
        test_discovery_and_probes(work_dir / "discovery")
        test_concurrent_single_path_publish(
            work_dir / "publish",
            post_build_hook=args.post_build_hook.resolve(),
            nix_bin=args.nix_bin.resolve(),
            sample_store_path=args.sample_store_path,
        )
        test_prune_caches_and_symlink_safety(work_dir / "gc")
    print("CHECK_RUNTIME_CACHE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
