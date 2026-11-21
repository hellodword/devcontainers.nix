#!/usr/bin/env python3
"""Publish latest and agent OCI manifests with preserved digests, immutable SHA tags, and master advancement checks."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
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
        if ref_name not in {"latest", "agent"}:
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
    if set(digests) != {"latest", "agent"}:
        raise PublishError(
            f"Expected both latest and agent manifests in {index_path}, got {sorted(digests)}"
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
    variant: str,
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
        f"oci:{oci_dir}:{variant}",
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
    agent_digest = result["localDigests"]["agent"]
    lines = [
        "## Devcontainer OCI Release Summary",
        "",
        f"- **Product commit**: `{result['commitSha']}`",
        f"- **Locked `core` commit (`flake.lock`)**: `{result['coreSha']}`",
        f"- **CI Action commit**: `{result['actionSha'] or 'local'}`",
        f"- **`:latest` manifest digest**: `{latest_digest}`",
        f"- **`:agent` manifest digest**: `{agent_digest}`",
        "",
        "### Tag Publication Status",
        "",
        "| Tag | Variant | Status | Remote Digest / Note |",
        "| --- | --- | --- | --- |",
    ]
    for tag_name, info in result["tags"].items():
        note = info.get("digest") or info.get("reason") or ""
        lines.append(
            f"| `{image_base}:{tag_name}` | `{info['variant']}` | `{info['status']}` | `{note}` |"
        )
    lines.extend(
        [
            "",
            "### Digest-Pinned Pull Commands",
            "",
            "```bash",
            f"# Interactive development & VS Code Dev Container (:latest / :sha-{result['commitSha']})",
            f"docker pull {image_base}@{latest_digest}",
            "",
            f"# Headless CLI & coding-agent runtime (:agent / :agent-sha-{result['commitSha']})",
            f"docker pull {image_base}@{agent_digest}",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def write_atomic_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def publish(args: argparse.Namespace) -> dict:
    commit_sha = args.commit_sha.strip().lower()
    if not HEX40_RE.match(commit_sha):
        raise PublishError(
            f"--commit-sha must be a 40-character lowercase hex SHA, got {args.commit_sha!r}"
        )

    oci_dir = args.oci_dir.resolve()
    tls_verify = args.tls_verify == "true"
    image_base = f"{args.registry}/{args.repository}"

    local_digests = parse_local_oci_digests(oci_dir)
    core_sha = args.core_sha or read_locked_core_sha(args.flake_lock)
    action_sha = args.action_sha or os.environ.get("NIX_CI_ACTION_SHA", "")

    tags_report: dict[str, dict[str, str]] = {}

    # Step 2: Immutable commit tags (`sha-<commit>` and `agent-sha-<commit>`).
    immutable_targets = [
        ("latest", f"sha-{commit_sha}"),
        ("agent", f"agent-sha-{commit_sha}"),
    ]
    for variant, tag_name in immutable_targets:
        full_ref = f"{image_base}:{tag_name}"
        expected = local_digests[variant]
        existing = inspect_remote_digest(
            full_ref, tls_verify=tls_verify, authfile=args.authfile
        )
        if existing is not None:
            if existing != expected:
                raise PublishError(
                    f"Digest conflict on immutable tag {full_ref}: "
                    f"remote already holds {existing}, refusing to overwrite with {expected}"
                )
            tags_report[tag_name] = {
                "variant": variant,
                "status": "reused",
                "digest": existing,
            }
        else:
            verified = copy_preserving_digest(
                oci_dir,
                variant,
                full_ref,
                expected,
                tls_verify=tls_verify,
                authfile=args.authfile,
            )
            tags_report[tag_name] = {
                "variant": variant,
                "status": "published",
                "digest": verified,
            }

    # Step 3: Floating tags (`:latest` then `:agent`), verifying remote master head before EACH tag.
    floating_targets = [
        ("latest", "latest"),
        ("agent", "agent"),
    ]
    master_advanced_reason: str | None = None
    for idx, (variant, tag_name) in enumerate(floating_targets):
        if idx == 1 and args.after_latest_hook:
            subprocess.run(args.after_latest_hook, shell=True, check=True, timeout=60)

        if master_advanced_reason is None:
            remote_master = query_remote_branch_sha(
                args.git_remote, args.expected_master_ref
            )
            if remote_master != commit_sha:
                master_advanced_reason = f"{args.expected_master_ref} advanced to {remote_master} (expected {commit_sha})"

        if master_advanced_reason is not None:
            tags_report[tag_name] = {
                "variant": variant,
                "status": "skipped",
                "reason": master_advanced_reason,
            }
            continue

        full_ref = f"{image_base}:{tag_name}"
        expected = local_digests[variant]
        verified = copy_preserving_digest(
            oci_dir,
            variant,
            full_ref,
            expected,
            tls_verify=tls_verify,
            authfile=args.authfile,
        )
        tags_report[tag_name] = {
            "variant": variant,
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

    if args.output_json is not None:
        write_atomic_text(
            args.output_json, json.dumps(result, indent=2, sort_keys=True) + "\n"
        )

    markdown = render_markdown_summary(result)
    if args.summary_file is not None:
        write_atomic_text(args.summary_file, markdown)
    elif env_summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(env_summary).open("a", encoding="utf-8") as handle:
            handle.write(markdown + "\n")

    print(json.dumps(result, sort_keys=True))
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--oci-dir", type=Path, required=True, help="Path to multi-variant OCI layout"
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
        "--commit-sha", required=True, help="40-character product commit SHA"
    )
    parser.add_argument(
        "--expected-master-ref",
        default="refs/heads/master",
        help="Git ref verified against --git-remote before moving floating tags",
    )
    parser.add_argument(
        "--git-remote", required=True, help="Upstream Git remote URL or path"
    )
    parser.add_argument(
        "--flake-lock",
        type=Path,
        default=Path("flake.lock"),
        help="Path to flake.lock for recording locked core revision",
    )
    parser.add_argument("--core-sha", default="", help="Override locked core revision")
    parser.add_argument(
        "--action-sha", default="", help="Running CI composite action commit SHA"
    )
    parser.add_argument(
        "--output-json",
        type=Path,
        default=Path("publish-result.json"),
        help="Output path for structured publication receipt",
    )
    parser.add_argument(
        "--summary-file",
        type=Path,
        default=None,
        help="Optional Markdown summary output file (defaults to GITHUB_STEP_SUMMARY when set)",
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
        "--after-latest-hook",
        default="",
        help=argparse.SUPPRESS,
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
