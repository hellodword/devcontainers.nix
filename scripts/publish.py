#!/usr/bin/env python3
"""Publish OCI manifest with preserved digest, immutable SHA tag, and master advancement check."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
NOT_FOUND_PATTERNS = (
    "manifest unknown",
    "name unknown",
    "not found",
    "status code 404",
    "404 (not found)",
)


class PublishError(RuntimeError):
    """Fatal publication error preserving existing remote state."""


def parse_local_oci_digests(oci_dir: Path) -> dict[str, str]:
    index_path = oci_dir / "index.json"
    if not index_path.is_file():
        raise PublishError(f"Missing index.json in {oci_dir}")
    index = json.loads(index_path.read_text(encoding="utf-8"))
    digests: dict[str, str] = {}
    for desc in index.get("manifests") or []:
        annotations = desc.get("annotations") or {}
        ref_name = annotations.get("org.opencontainers.image.ref.name")
        if ref_name != "latest":
            continue
        expected_digest = desc.get("digest", "")
        if not expected_digest.startswith("sha256:"):
            raise PublishError(
                f"Unsupported digest for {ref_name}: {expected_digest!r}"
            )
        blob = oci_dir / "blobs" / "sha256" / expected_digest.split(":", 1)[1]
        if not blob.is_file():
            raise PublishError(f"Missing manifest blob {blob} for {ref_name}")
        raw = blob.read_bytes()
        actual_digest = "sha256:" + hashlib.sha256(raw).hexdigest()
        if actual_digest != expected_digest:
            raise PublishError(
                f"Local OCI manifest digest mismatch for {ref_name}: {actual_digest} != {expected_digest}"
            )
        digests[ref_name] = expected_digest
    if set(digests) != {"latest"}:
        raise PublishError(
            f"Expected latest manifest in {index_path}, got {sorted(digests)}"
        )
    return digests


def read_locked_core_sha(flake_lock: Path) -> str:
    if not flake_lock.is_file():
        return "unknown"
    try:
        data = json.loads(flake_lock.read_text(encoding="utf-8"))
        root_name = data.get("root", "root")
        core_node = data["nodes"][root_name]["inputs"]["core"]
        if isinstance(core_node, list):
            node = root_name
            for part in core_node:
                node = data["nodes"][node]["inputs"][part]
            core_node = node
        return str(data["nodes"][core_node]["locked"]["rev"])
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        return "unknown"


def skopeo_auth_args(authfile: Path | None) -> list[str]:
    if authfile is not None:
        return ["--authfile", str(authfile)]
    return []


def resolve_oci_dir(oci_dir: Path | None, manifest_path: Path | None) -> Path:
    if oci_dir is not None:
        return oci_dir.resolve()
    if manifest_path is None or not manifest_path.is_file():
        raise PublishError("Provide --oci-dir or an existing --manifest file")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for group in manifest.get("groups") or []:
        if group.get("name") == "build":
            for entry in group.get("entries") or []:
                if entry.get("name") == "oci" and entry.get("outputs"):
                    return Path(entry["outputs"][0]).resolve()
    raise PublishError(f"Could not find build/oci output in {manifest_path}")


@contextmanager
def prepared_authfile(
    *,
    registry: str,
    tls_verify: bool,
    authfile: Path | None,
    login_env: bool,
):
    if not login_env:
        yield authfile
        return
    actor = os.environ.get("GITHUB_ACTOR", "").strip()
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not actor or not token:
        raise PublishError(
            "GITHUB_ACTOR and GITHUB_TOKEN must be set when --login-env is enabled"
        )
    with tempfile.TemporaryDirectory(prefix="ghcr-auth-") as tmp_dir:
        temp_auth = Path(tmp_dir) / "auth.json"
        res = subprocess.run(
            [
                "skopeo",
                "login",
                registry,
                f"--tls-verify={'true' if tls_verify else 'false'}",
                "--username",
                actor,
                "--password-stdin",
                "--authfile",
                str(temp_auth),
            ],
            input=token,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
        if res.returncode != 0:
            raise PublishError(
                f"skopeo login failed for {registry} (exit {res.returncode}): {res.stderr.strip()}"
            )
        yield temp_auth


def inspect_remote_digest(
    target_ref: str,
    *,
    tls_verify: bool,
    authfile: Path | None,
) -> str | None:
    cmd = [
        "skopeo",
        "--insecure-policy",
        "inspect",
        "--raw",
        f"--tls-verify={'true' if tls_verify else 'false'}",
        *skopeo_auth_args(authfile),
        f"docker://{target_ref}",
    ]
    res = subprocess.run(cmd, capture_output=True, check=False, timeout=120)
    if res.returncode == 0:
        if not res.stdout:
            raise PublishError(f"Empty raw manifest returned for {target_ref}")
        return "sha256:" + hashlib.sha256(res.stdout).hexdigest()

    stderr_text = res.stderr.decode("utf-8", errors="replace").strip()
    lowered = stderr_text.lower()
    if any(pat in lowered for pat in NOT_FOUND_PATTERNS):
        return None
    raise PublishError(
        f"Failed to inspect remote tag {target_ref} (exit {res.returncode}): {stderr_text}"
    )


def copy_preserving_digest(
    oci_dir: Path,
    ref_name: str,
    target_ref: str,
    expected_digest: str,
    *,
    tls_verify: bool,
    authfile: Path | None,
) -> str:
    cmd = [
        "skopeo",
        "--insecure-policy",
        "copy",
        "--preserve-digests",
        f"--dest-tls-verify={'true' if tls_verify else 'false'}",
        *skopeo_auth_args(authfile),
        f"oci:{oci_dir}:{ref_name}",
        f"docker://{target_ref}",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=1800)
    if res.returncode != 0:
        raise PublishError(
            f"skopeo copy failed for {target_ref} (exit {res.returncode}): {res.stderr.strip()}"
        )
    verified = inspect_remote_digest(
        target_ref, tls_verify=tls_verify, authfile=authfile
    )
    if verified != expected_digest:
        raise PublishError(
            f"Remote manifest digest mismatch after pushing {target_ref}: "
            f"remote {verified} != expected {expected_digest}"
        )
    return verified


def query_remote_branch_sha(git_remote: str, expected_ref: str) -> str:
    res = subprocess.run(
        ["git", "ls-remote", "--exit-code", git_remote, expected_ref],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    if res.returncode != 0:
        raise PublishError(
            f"git ls-remote failed for {git_remote} {expected_ref} (exit {res.returncode}): "
            f"{res.stderr.strip()}"
        )
    for line in res.stdout.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2 and parts[1] == expected_ref:
            sha = parts[0].lower()
            if not HEX40_RE.match(sha):
                raise PublishError(f"Unexpected commit SHA from git ls-remote: {sha!r}")
            return sha
    raise PublishError(f"Ref {expected_ref} not found in {git_remote}")


def render_markdown_summary(result: dict) -> str:
    image_base = f"{result['registry']}/{result['repository']}"
    latest_digest = result["localDigests"]["latest"]
    lines = [
        "## Devcontainer OCI Release Summary",
        "",
        f"- **Product commit**: `{result['commitSha']}`",
        f"- **Locked `core` commit (`flake.lock`)**: `{result['coreSha']}`",
        f"- **CI Action commit**: `{result['actionSha'] or 'local'}`",
        f"- **Manifest digest**: `{latest_digest}`",
        "",
        "### Tag Publication Status",
        "",
        "| Tag | Status | Remote Digest / Note |",
        "| --- | --- | --- |",
    ]
    for tag_name, info in result["tags"].items():
        note = info.get("digest") or info.get("reason") or ""
        lines.append(f"| `{image_base}:{tag_name}` | `{info['status']}` | `{note}` |")
    lines.extend(
        [
            "",
            "### Digest-Pinned Pull Command",
            "",
            "```bash",
            f"docker pull {image_base}@{latest_digest}",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def publish(args: argparse.Namespace) -> dict:
    tls_verify = args.tls_verify == "true"
    with prepared_authfile(
        registry=args.registry,
        tls_verify=tls_verify,
        authfile=args.authfile,
        login_env=args.login_env,
    ) as active_authfile:
        if args.preflight_only:
            if active_authfile is None:
                raise PublishError(
                    "--preflight-only requires --login-env or --authfile"
                )
            result = {"preflight": "ok", "registry": args.registry}
            print(json.dumps(result, sort_keys=True))
            return result

        if not args.commit_sha or not args.git_remote:
            raise PublishError("--commit-sha and --git-remote are required")
        commit_sha = args.commit_sha.strip().lower()
        if not HEX40_RE.match(commit_sha):
            raise PublishError(
                f"--commit-sha must be a 40-character lowercase hex SHA, got {args.commit_sha!r}"
            )

        oci_dir = resolve_oci_dir(args.oci_dir, args.manifest)
        return _publish_with_auth(
            args, oci_dir, commit_sha, tls_verify, active_authfile
        )


def _publish_with_auth(
    args: argparse.Namespace,
    oci_dir: Path,
    commit_sha: str,
    tls_verify: bool,
    authfile: Path | None,
) -> dict:
    image_base = f"{args.registry}/{args.repository}"

    local_digests = parse_local_oci_digests(oci_dir)
    expected = local_digests["latest"]
    core_sha = read_locked_core_sha(args.flake_lock)
    action_sha = args.action_sha

    tags_report: dict[str, dict[str, str]] = {}

    sha_tag = f"sha-{commit_sha}"
    sha_ref = f"{image_base}:{sha_tag}"
    existing = inspect_remote_digest(sha_ref, tls_verify=tls_verify, authfile=authfile)
    if existing is not None:
        if existing != expected:
            raise PublishError(
                f"Digest conflict on immutable tag {sha_ref}: "
                f"remote already holds {existing}, refusing to overwrite with {expected}"
            )
        tags_report[sha_tag] = {
            "status": "reused",
            "digest": existing,
        }
    else:
        verified = copy_preserving_digest(
            oci_dir,
            "latest",
            sha_ref,
            expected,
            tls_verify=tls_verify,
            authfile=authfile,
        )
        tags_report[sha_tag] = {
            "status": "published",
            "digest": verified,
        }

    remote_master = query_remote_branch_sha(args.git_remote, args.expected_master_ref)
    if remote_master != commit_sha:
        tags_report["latest"] = {
            "status": "skipped",
            "reason": f"{args.expected_master_ref} advanced to {remote_master} (expected {commit_sha})",
        }
    else:
        latest_ref = f"{image_base}:latest"
        verified = copy_preserving_digest(
            oci_dir,
            "latest",
            latest_ref,
            expected,
            tls_verify=tls_verify,
            authfile=authfile,
        )
        tags_report["latest"] = {
            "status": "published",
            "digest": verified,
        }

    result = {
        "registry": args.registry,
        "repository": args.repository,
        "commitSha": commit_sha,
        "coreSha": core_sha,
        "actionSha": action_sha,
        "expectedMasterRef": args.expected_master_ref,
        "localDigests": local_digests,
        "tags": tags_report,
    }

    if env_summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        summary_path = Path(env_summary)
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        with summary_path.open("a", encoding="utf-8") as handle:
            handle.write(render_markdown_summary(result) + "\n")

    print(json.dumps(result, sort_keys=True))
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--oci-dir", type=Path, default=None, help="Path to OCI layout directory"
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=None,
        help="Path to nix-ci manifest.json used to resolve build/oci output",
    )
    parser.add_argument(
        "--registry", default="ghcr.io", help="Target OCI registry host"
    )
    parser.add_argument(
        "--repository",
        default="hellodword/devcontainers-dev",
        help="Target OCI repository path",
    )
    parser.add_argument(
        "--commit-sha", default="", help="40-character product commit SHA"
    )
    parser.add_argument(
        "--expected-master-ref",
        default="refs/heads/master",
        help="Git ref verified against --git-remote before moving floating :latest",
    )
    parser.add_argument(
        "--git-remote", default="", help="Upstream Git remote URL or path"
    )
    parser.add_argument(
        "--flake-lock",
        type=Path,
        default=Path("flake.lock"),
        help="Path to flake.lock for recording locked core revision",
    )
    parser.add_argument(
        "--action-sha", default="", help="Running CI composite action commit SHA"
    )
    parser.add_argument(
        "--tls-verify",
        choices=("true", "false"),
        default="true",
        help="Verify registry TLS certificates (set false only for local loopback test registries)",
    )
    parser.add_argument(
        "--authfile", type=Path, default=None, help="Optional skopeo authfile path"
    )
    parser.add_argument(
        "--login-env",
        action="store_true",
        help="Authenticate skopeo using GITHUB_ACTOR and GITHUB_TOKEN in a temporary authfile",
    )
    parser.add_argument(
        "--preflight-only",
        action="store_true",
        help="Verify registry credentials and exit without publishing tags",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        publish(args)
    except PublishError as err:
        print(f"publish error: {err}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
