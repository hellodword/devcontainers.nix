#!/usr/bin/env python3
"""Validate OCI layout invariants, layer budgets, cache-layout parity, and directory ownership."""

from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MAX_LAYER_BYTES = 8 * 1024 * 1024 * 1024  # 8589934592 bytes (8 GiB)

REQUIRED_COMMANDS = {
    "agy",
    "bash",
    "buf",
    "cargo",
    "ccache",
    "cmake",
    "codex",
    "curl",
    "devcontainer-entrypoint",
    "devcontainer-gui-env",
    "devcontainer-runtime",
    "devcontainer-set-user-id",
    "devcontainer-task-runner",
    "devpkg",
    "docker",
    "eslint",
    "fd",
    "gcc",
    "git",
    "go",
    "gopls",
    "gpg",
    "jq",
    "just",
    "ninja",
    "nix",
    "nixd",
    "nixfmt",
    "node",
    "npm",
    "opencode",
    "pnpm",
    "prettier",
    "protoc",
    "python3",
    "rg",
    "ruff",
    "rust-analyzer",
    "rustc",
    "rustup",
    "shellcheck",
    "shfmt",
    "ssh",
    "taplo",
    "uv",
    "vm-test-submit",
    "wayland-info",
}

FORBIDDEN_COMMANDS = {"gh"}

EXPECTED_PATH = (
    "/home/vscode/.local/share/devcontainer/bin:"
    "/home/vscode/.local/share/nix-profile/bin:"
    "/home/vscode/.nix-profile/bin:"
    "/home/vscode/.local/share/cargo/bin:"
    "/home/vscode/.local/share/go/bin:"
    "/home/vscode/.local/share/uv/bin:"
    "/home/vscode/.local/share/python/bin:"
    "/home/vscode/.local/share/pnpm:"
    "/usr/local/bin:"
    "/usr/bin"
)

EXPECTED_TOOLCHAIN_ENV = {
    "CARGO_HOME": "/home/vscode/.local/share/cargo",
    "CCACHE_DIR": "/home/vscode/.cache/ccache",
    "CCACHE_MAXSIZE": "20G",
    "COREPACK_HOME": "/home/vscode/.cache/corepack",
    "GOBIN": "/home/vscode/.local/share/go/bin",
    "GOCACHE": "/home/vscode/.cache/go-build",
    "GOMODCACHE": "/home/vscode/.cache/go/pkg/mod",
    "GOPATH": "/home/vscode/.local/share/go",
    "NPM_CONFIG_CACHE": "/home/vscode/.cache/npm",
    "PIP_CACHE_DIR": "/home/vscode/.cache/pip",
    "PNPM_CONFIG_PACKAGE_IMPORT_METHOD": "copy",
    "PNPM_CONFIG_STORE_DIR": "/home/vscode/.cache/pnpm/store",
    "PNPM_HOME": "/home/vscode/.local/share/pnpm",
    "PYTHONUSERBASE": "/home/vscode/.local/share/python",
    "RUSTUP_HOME": "/home/vscode/.local/share/rustup",
    "UV_CACHE_DIR": "/home/vscode/.cache/uv",
    "UV_LINK_MODE": "copy",
    "UV_TOOL_BIN_DIR": "/home/vscode/.local/share/uv/bin",
    "UV_TOOL_DIR": "/home/vscode/.local/share/uv/tools",
    "YARN_CACHE_FOLDER": "/home/vscode/.cache/yarn",
}

REQUIRED_DEV_ENV_KEYS = {
    "BINDGEN_EXTRA_CLANG_ARGS",
    "CGO_CFLAGS",
    "CGO_LDFLAGS",
    "GOTELEMETRY",
    "GOTOOLCHAIN",
    "NIX_CFLAGS_COMPILE",
    "NIX_LDFLAGS",
    "NODE_ENV",
    "NODE_REPL_HISTORY",
    "RUST_BACKTRACE",
}

ISOLATED_PROJECT_ENV_KEYS = {
    "MYPY_CACHE_DIR",
    "PYTHONPYCACHEPREFIX",
}


def blob_path(oci_dir: Path, digest: str) -> Path:
    if not digest.startswith("sha256:"):
        raise AssertionError(f"Unsupported digest algorithm: {digest}")
    hex_digest = digest.split(":", 1)[1]
    path = oci_dir / "blobs" / "sha256" / hex_digest
    if not path.is_file():
        raise AssertionError(f"Missing blob file: {path}")
    return path


def read_verified_json(oci_dir: Path, descriptor: dict) -> dict:
    path = blob_path(oci_dir, descriptor["digest"])
    raw = path.read_bytes()
    actual_size = len(raw)
    if actual_size != descriptor["size"]:
        raise AssertionError(
            f"Size mismatch for {descriptor['digest']}: {actual_size} != {descriptor['size']}"
        )
    actual_digest = "sha256:" + hashlib.sha256(raw).hexdigest()
    if actual_digest != descriptor["digest"]:
        raise AssertionError(
            f"Digest mismatch: {actual_digest} != {descriptor['digest']}"
        )
    return json.loads(raw.decode("utf-8"))


def parse_env_list(env_list: list[str]) -> dict[str, str]:
    parsed = {}
    for entry in env_list:
        if "=" not in entry:
            raise AssertionError(f"Malformed Env entry: {entry!r}")
        key, val = entry.split("=", 1)
        parsed[key] = val
    return parsed


def home_ancestors(target: str) -> set[str]:
    prefix = "/home/vscode/"
    if not target.startswith(prefix):
        return set()
    parts = [p for p in target[len(prefix) :].split("/") if p]
    return {"home/vscode/" + "/".join(parts[:idx]) for idx in range(1, len(parts))}


def inspect_top_layer(
    layer_blob: Path,
) -> tuple[set[str], set[str], dict[str, tuple[int, int, int]], bytes | None]:
    commands: set[str] = set()
    sbin_entries: set[str] = set()
    dirs: dict[str, tuple[int, int, int]] = {}
    embedded_layout: bytes | None = None

    with tarfile.open(layer_blob, mode="r:*") as archive:
        for member in archive.getmembers():
            norm = member.name.lstrip("./").rstrip("/")
            if member.isdir() and norm:
                dirs[norm] = (member.uid, member.gid, member.mode & 0o7777)
            if norm == "usr/share/devcontainer/cache-layout.json" and member.isfile():
                extracted = archive.extractfile(member)
                if extracted is not None:
                    embedded_layout = extracted.read()
            parts = norm.split("/")
            if len(parts) == 3 and parts[0] == "usr" and parts[1] == "bin" and parts[2]:
                commands.add(parts[2])
            if (
                len(parts) == 3
                and parts[0] == "usr"
                and parts[1] == "sbin"
                and parts[2]
            ):
                sbin_entries.add(parts[2])
    return commands, sbin_entries, dirs, embedded_layout


def check_layout(oci_dir: Path, cache_layout_path: Path) -> dict:
    expected_cache_layout = json.loads(cache_layout_path.read_text(encoding="utf-8"))
    assert expected_cache_layout.get("version") == 1, expected_cache_layout
    mounts = expected_cache_layout.get("mounts") or []
    assert len(mounts) == 20, len(mounts)

    oci_layout_file = oci_dir / "oci-layout"
    assert oci_layout_file.is_file(), f"Missing {oci_layout_file}"
    layout_meta = json.loads(oci_layout_file.read_text(encoding="utf-8"))
    assert layout_meta.get("imageLayoutVersion") == "1.0.0", layout_meta

    index_path = oci_dir / "index.json"
    assert index_path.is_file(), f"Missing {index_path}"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    manifests = index.get("manifests")
    assert isinstance(manifests, list) and len(manifests) == 1, (
        f"Expected exactly 1 manifest in index.json, got {manifests}"
    )

    desc = manifests[0]
    annotations = desc.get("annotations") or {}
    ref = annotations.get("org.opencontainers.image.ref.name")
    assert ref == "latest", f"Unexpected manifest ref annotation: {desc}"

    manifest = read_verified_json(oci_dir, desc)
    layers = manifest["layers"]
    assert len(layers) == 7, f"Expected 7 layers (6 store + 1 top), got {len(layers)}"

    for idx, layer in enumerate(layers):
        media_type = layer.get("mediaType", "")
        assert media_type.endswith(("+gzip", "+zstd")), (idx, media_type)
        path = blob_path(oci_dir, layer["digest"])
        actual_bytes = path.stat().st_size
        assert actual_bytes == layer["size"], (idx, actual_bytes, layer["size"])
        assert 0 < actual_bytes <= MAX_LAYER_BYTES, (
            f"Layer {idx} ({layer['digest']}) size {actual_bytes} exceeds 8 GiB budget"
        )

    cfg = read_verified_json(oci_dir, manifest["config"])["config"]
    assert cfg.get("User") == "vscode", cfg.get("User")
    assert cfg.get("WorkingDir") == "/workspaces", cfg.get("WorkingDir")
    assert cfg.get("Entrypoint") == ["/usr/bin/devcontainer-entrypoint"], cfg.get(
        "Entrypoint"
    )
    assert cfg.get("Cmd") == ["/bin/bash"], cfg.get("Cmd")

    labels = cfg.get("Labels") or {}
    for required_label in (
        "org.opencontainers.image.revision",
        "org.opencontainers.image.version",
        "devcontainers.nix.revision",
        "devcontainers.nix.version",
        "devcontainers.nix.dirty",
        "devcontainers.nix.cache-layout",
        "devcontainer.metadata",
    ):
        assert required_label in labels and labels[required_label] != "", required_label

    label_cache_layout = json.loads(labels["devcontainers.nix.cache-layout"])
    assert label_cache_layout == expected_cache_layout, (
        "OCI label devcontainers.nix.cache-layout differs from data/cache-layout.json"
    )

    meta_list = json.loads(labels["devcontainer.metadata"])
    assert isinstance(meta_list, list) and len(meta_list) == 1, meta_list
    meta = meta_list[0]
    assert meta.get("init") is True, meta
    assert meta.get("overrideCommand") is True, meta
    assert meta.get("remoteUser") == "vscode", meta
    assert meta.get("containerUser") == "vscode", meta
    assert meta.get("updateRemoteUserUID") is False, meta
    assert meta.get("privileged") is False, meta
    assert meta.get("securityOpt") == ["label=disable"], meta
    assert meta.get("userEnvProbe") == "loginInteractiveShell", meta
    assert "postCreateCommand" in meta and "postStartCommand" in meta, meta
    assert any(
        "readonly" in m and ".devcontainer" in m for m in meta.get("mounts", [])
    ), meta

    env = parse_env_list(cfg.get("Env") or [])
    assert env.get("PATH") == EXPECTED_PATH, env.get("PATH")

    for key, expected_val in EXPECTED_TOOLCHAIN_ENV.items():
        assert env.get(key) == expected_val, (
            f"Unexpected {key} in Env: {env.get(key)!r} != {expected_val!r}"
        )

    for item in mounts:
        env_key = item.get("env")
        if env_key is not None:
            assert env.get(env_key) == item["target"], (
                f"Cache layout env {env_key} mismatch: {env.get(env_key)!r} != {item['target']!r}"
            )

    for key in REQUIRED_DEV_ENV_KEYS:
        assert key in env, f"Missing {key} in Env"

    for key in ISOLATED_PROJECT_ENV_KEYS:
        assert key not in env, f"Unexpected cross-project cache variable in Env: {key}"

    top_blob = blob_path(oci_dir, layers[-1]["digest"])
    cmds, sbin, dirs, embedded_layout = inspect_top_layer(top_blob)

    assert embedded_layout is not None, (
        "Missing /usr/share/devcontainer/cache-layout.json in top layer"
    )
    assert json.loads(embedded_layout.decode("utf-8")) == expected_cache_layout

    assert dirs.get("workspaces") == (0, 0, 0o1777), dirs.get("workspaces")
    assert dirs.get("var") == (0, 0, 0o755), dirs.get("var")
    assert dirs.get("var/cache") == (0, 0, 0o755), dirs.get("var/cache")

    expected_user_dirs = {
        "home/vscode/.codex",
        "home/vscode/.gemini",
        "home/vscode/.config/opencode",
        "home/vscode/.local/share/opencode",
        "home/vscode/.local/state/opencode",
    }
    for item in mounts:
        norm_target = item["target"].lstrip("/")
        expected_mode = int(item["mode"], 8)
        assert dirs.get(norm_target) == (1000, 1000, expected_mode), (
            f"Expected {norm_target} owned by 1000:1000 mode {oct(expected_mode)}, got {dirs.get(norm_target)}"
        )
        expected_user_dirs |= home_ancestors(item["target"])

    for rel_dir in sorted(expected_user_dirs):
        entry = dirs.get(rel_dir)
        assert entry is not None and entry[:2] == (1000, 1000), (
            f"Expected {rel_dir} pre-created as 1000:1000 in image, got {entry}"
        )

    assert "ldconfig" not in sbin, sbin
    assert not (FORBIDDEN_COMMANDS & cmds), FORBIDDEN_COMMANDS & cmds
    missing_cmds = REQUIRED_COMMANDS - cmds
    assert not missing_cmds, f"Missing commands in /usr/bin: {sorted(missing_cmds)}"

    summary = {
        "latestDigest": desc["digest"],
        "layers": len(layers),
        "cachePools": len(mounts),
        "usrBinCount": len(cmds),
    }
    print("OCI_LAYOUT_OK", json.dumps(summary, sort_keys=True))
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("oci_dir", type=Path, help="Path to OCI layout directory")
    parser.add_argument(
        "--cache-layout",
        type=Path,
        default=REPO_ROOT / "data" / "cache-layout.json",
        help="Path to data/cache-layout.json",
    )
    args = parser.parse_args(argv)
    check_layout(args.oci_dir, args.cache_layout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
