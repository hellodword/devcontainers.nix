#!/usr/bin/env python3
"""Validate shared OCI layout invariants, layer deduplication, 8 GiB budget, and variant boundaries."""

from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
from pathlib import Path

MAX_LAYER_BYTES = 8 * 1024 * 1024 * 1024  # 8589934592 bytes (8 GiB)

SHARED_REQUIRED_COMMANDS = {
    "agy",
    "bash",
    "codex",
    "curl",
    "devcontainer-entrypoint",
    "devcontainer-gui-env",
    "devcontainer-runtime",
    "devcontainer-set-user-id",
    "devpkg",
    "docker",
    "fd",
    "git",
    "gpg",
    "jq",
    "just",
    "nix",
    "opencode",
    "rg",
    "ssh",
    "vm-test-submit",
}

LATEST_ONLY_COMMANDS = {
    "buf",
    "cargo",
    "cmake",
    "devcontainer-task-runner",
    "eslint",
    "gcc",
    "go",
    "gopls",
    "ninja",
    "nixd",
    "nixfmt",
    "node",
    "npm",
    "pnpm",
    "prettier",
    "protoc",
    "python3",
    "ruff",
    "rust-analyzer",
    "rustc",
    "rustup",
    "shellcheck",
    "shfmt",
    "taplo",
    "uv",
    "wayland-info",
}

FORBIDDEN_COMMANDS = {"gh"}

AGENT_EXPECTED_PATH = (
    "/home/vscode/.local/share/devcontainer/bin:"
    "/home/vscode/.local/share/nix-profile/bin:"
    "/home/vscode/.nix-profile/bin:"
    "/usr/local/bin:"
    "/usr/bin"
)

LATEST_EXPECTED_PATH = (
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

LATEST_ONLY_ENV_KEYS = {
    "BINDGEN_EXTRA_CLANG_ARGS",
    "CARGO_HOME",
    "CGO_CFLAGS",
    "CGO_LDFLAGS",
    "COREPACK_HOME",
    "GOCACHE",
    "GOMODCACHE",
    "GOPATH",
    "GOTOOLCHAIN",
    "MYPY_CACHE_DIR",
    "NIX_CFLAGS_COMPILE",
    "NIX_LDFLAGS",
    "NODE_ENV",
    "NPM_CONFIG_CACHE",
    "PNPM_HOME",
    "PYTHONUSERBASE",
    "RUSTUP_HOME",
    "UV_CACHE_DIR",
    "UV_TOOL_BIN_DIR",
    "YARN_CACHE_FOLDER",
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


def extract_usr_bin_commands(layer_blob: Path) -> tuple[set[str], set[str]]:
    commands: set[str] = set()
    sbin_entries: set[str] = set()
    with tarfile.open(layer_blob, mode="r:*") as archive:
        for member in archive.getmembers():
            norm = member.name.lstrip("./")
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
    return commands, sbin_entries


def check_layout(oci_dir: Path) -> dict:
    oci_layout_file = oci_dir / "oci-layout"
    assert oci_layout_file.is_file(), f"Missing {oci_layout_file}"
    layout_meta = json.loads(oci_layout_file.read_text(encoding="utf-8"))
    assert layout_meta.get("imageLayoutVersion") == "1.0.0", layout_meta

    index_path = oci_dir / "index.json"
    assert index_path.is_file(), f"Missing {index_path}"
    index = json.loads(index_path.read_text(encoding="utf-8"))
    manifests = index.get("manifests")
    assert isinstance(manifests, list) and len(manifests) == 2, (
        f"Expected exactly 2 manifests in index.json, got {manifests}"
    )

    by_ref = {}
    for desc in manifests:
        annotations = desc.get("annotations") or {}
        ref = annotations.get("org.opencontainers.image.ref.name")
        assert ref in {"latest", "agent"}, f"Unexpected manifest ref annotation: {desc}"
        assert ref not in by_ref, f"Duplicate manifest ref {ref}"
        by_ref[ref] = desc

    assert set(by_ref) == {"latest", "agent"}, set(by_ref)

    latest_manifest = read_verified_json(oci_dir, by_ref["latest"])
    agent_manifest = read_verified_json(oci_dir, by_ref["agent"])

    latest_layers = latest_manifest["layers"]
    agent_layers = agent_manifest["layers"]

    assert len(latest_layers) >= 7 and len(agent_layers) >= 5, (
        len(latest_layers),
        len(agent_layers),
    )
    assert len(latest_layers) - len(agent_layers) == 2, (
        f"Expected :agent to have 2 fewer layers than :latest, got "
        f"latest={len(latest_layers)} vs agent={len(agent_layers)}"
    )

    # First 4 layers (foundation, toolchains, agents-oss, agents-restricted) must be identical & deduplicated.
    for idx in range(4):
        l_desc = latest_layers[idx]
        a_desc = agent_layers[idx]
        assert l_desc["digest"] == a_desc["digest"], (
            f"Shared layer {idx} digest mismatch: {l_desc['digest']} != {a_desc['digest']}"
        )
        assert l_desc["size"] == a_desc["size"], (
            f"Shared layer {idx} size mismatch: {l_desc['size']} != {a_desc['size']}"
        )
        shared_file = blob_path(oci_dir, l_desc["digest"])
        assert shared_file.stat().st_size == l_desc["size"]

    # Every compressed layer across both manifests must stay strictly <= 8 GiB.
    for variant, layers in (("latest", latest_layers), ("agent", agent_layers)):
        for idx, layer in enumerate(layers):
            media_type = layer.get("mediaType", "")
            assert media_type.endswith(("+gzip", "+zstd")), (variant, idx, media_type)
            path = blob_path(oci_dir, layer["digest"])
            actual_bytes = path.stat().st_size
            assert actual_bytes == layer["size"], (
                variant,
                idx,
                actual_bytes,
                layer["size"],
            )
            assert 0 < actual_bytes <= MAX_LAYER_BYTES, (
                f"{variant} layer {idx} ({layer['digest']}) size {actual_bytes} exceeds 8 GiB budget"
            )

    latest_cfg = read_verified_json(oci_dir, latest_manifest["config"])["config"]
    agent_cfg = read_verified_json(oci_dir, agent_manifest["config"])["config"]

    for variant, cfg in (("latest", latest_cfg), ("agent", agent_cfg)):
        assert cfg.get("User") == "vscode", (variant, cfg.get("User"))
        assert cfg.get("WorkingDir") == "/workspaces", (variant, cfg.get("WorkingDir"))
        assert cfg.get("Entrypoint") == ["/usr/bin/devcontainer-entrypoint"], (
            variant,
            cfg.get("Entrypoint"),
        )
        assert cfg.get("Cmd") == ["/bin/bash"], (variant, cfg.get("Cmd"))
        labels = cfg.get("Labels") or {}
        for required_label in (
            "org.opencontainers.image.revision",
            "org.opencontainers.image.version",
            "devcontainers.nix.revision",
            "devcontainers.nix.version",
            "devcontainers.nix.dirty",
        ):
            assert required_label in labels and labels[required_label] != "", (
                variant,
                required_label,
            )

    latest_labels = latest_cfg.get("Labels") or {}
    agent_labels = agent_cfg.get("Labels") or {}
    assert "devcontainer.metadata" in latest_labels, (
        "latest must carry devcontainer.metadata label"
    )
    assert "devcontainer.metadata" not in agent_labels, (
        "agent must NOT carry devcontainer.metadata label"
    )

    meta_list = json.loads(latest_labels["devcontainer.metadata"])
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

    latest_env = parse_env_list(latest_cfg.get("Env") or [])
    agent_env = parse_env_list(agent_cfg.get("Env") or [])
    assert latest_env.get("PATH") == LATEST_EXPECTED_PATH, latest_env.get("PATH")
    assert agent_env.get("PATH") == AGENT_EXPECTED_PATH, agent_env.get("PATH")

    for key in LATEST_ONLY_ENV_KEYS:
        assert key in latest_env, f"Missing {key} in :latest Env"
        assert key not in agent_env, (
            f"Unexpected toolchain env {key} leaked into :agent Env"
        )

    latest_top_blob = blob_path(oci_dir, latest_layers[-1]["digest"])
    agent_top_blob = blob_path(oci_dir, agent_layers[-1]["digest"])
    latest_cmds, latest_sbin = extract_usr_bin_commands(latest_top_blob)
    agent_cmds, agent_sbin = extract_usr_bin_commands(agent_top_blob)

    assert "ldconfig" not in latest_sbin and "ldconfig" not in agent_sbin, (
        latest_sbin,
        agent_sbin,
    )

    assert not (FORBIDDEN_COMMANDS & latest_cmds), (
        f"Forbidden command in :latest: {FORBIDDEN_COMMANDS & latest_cmds}"
    )
    assert not (FORBIDDEN_COMMANDS & agent_cmds), (
        f"Forbidden command in :agent: {FORBIDDEN_COMMANDS & agent_cmds}"
    )

    missing_shared_latest = SHARED_REQUIRED_COMMANDS - latest_cmds
    missing_shared_agent = SHARED_REQUIRED_COMMANDS - agent_cmds
    assert not missing_shared_latest, (
        f"Missing shared commands in :latest: {sorted(missing_shared_latest)}"
    )
    assert not missing_shared_agent, (
        f"Missing shared commands in :agent: {sorted(missing_shared_agent)}"
    )

    missing_latest_only = LATEST_ONLY_COMMANDS - latest_cmds
    assert not missing_latest_only, (
        f"Missing toolchain commands in :latest: {sorted(missing_latest_only)}"
    )

    leaked_agent_cmds = LATEST_ONLY_COMMANDS & agent_cmds
    assert not leaked_agent_cmds, (
        f"Toolchain/editor commands leaked into :agent /usr/bin: {sorted(leaked_agent_cmds)}"
    )

    summary = {
        "latestDigest": by_ref["latest"]["digest"],
        "agentDigest": by_ref["agent"]["digest"],
        "latestLayers": len(latest_layers),
        "agentLayers": len(agent_layers),
        "sharedLayerDigests": [d["digest"] for d in latest_layers[:4]],
        "latestUsrBinCount": len(latest_cmds),
        "agentUsrBinCount": len(agent_cmds),
    }
    print("OCI_LAYOUT_OK", json.dumps(summary, sort_keys=True))
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "oci_dir", type=Path, help="Path to shared OCI layout directory"
    )
    args = parser.parse_args(argv)
    check_layout(args.oci_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
