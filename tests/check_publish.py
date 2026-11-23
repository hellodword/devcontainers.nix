#!/usr/bin/env python3
"""Workflow 3 verification: 4-tag digest-preserving OCI release, conflict protection, and recovery."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from contextlib import contextmanager, redirect_stdout
from pathlib import Path
from unittest.mock import patch

REPO_ROOT = Path(__file__).resolve().parent.parent
PUBLISH_PY = REPO_ROOT / "scripts" / "publish.py"


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def sha256_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def make_gzip_layer(files: dict[str, bytes]) -> tuple[bytes, str]:
    tar_buf = io.BytesIO()
    with tarfile.open(fileobj=tar_buf, mode="w", format=tarfile.PAX_FORMAT) as tf:
        for name, content in sorted(files.items()):
            info = tarfile.TarInfo(name=name)
            info.size = len(content)
            info.mode = 0o644
            info.uid = 1000
            info.gid = 1000
            info.mtime = 1
            tf.addfile(info, io.BytesIO(content))
    uncompressed = tar_buf.getvalue()
    diff_id = sha256_bytes(uncompressed)
    gz_buf = io.BytesIO()
    with gzip.GzipFile(fileobj=gz_buf, mode="wb", mtime=1) as gz:
        gz.write(uncompressed)
    return gz_buf.getvalue(), diff_id


def build_synthetic_oci_layout(dest: Path, marker: str = "v1") -> dict[str, str]:
    blobs = dest / "blobs" / "sha256"
    blobs.mkdir(parents=True, exist_ok=True)
    (dest / "oci-layout").write_text(
        json.dumps({"imageLayoutVersion": "1.0.0"}) + "\n", encoding="utf-8"
    )

    def write_blob(raw: bytes) -> dict[str, object]:
        digest = sha256_bytes(raw)
        (blobs / digest.split(":", 1)[1]).write_bytes(raw)
        return {"digest": digest, "size": len(raw)}

    shared_gz, shared_diff = make_gzip_layer(
        {"nix/store/shared-base": f"shared-{marker}\n".encode()}
    )
    shared_desc = {
        **write_blob(shared_gz),
        "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
    }

    manifests_index = []
    variant_digests: dict[str, str] = {}

    for variant in ("latest", "agent"):
        top_gz, top_diff = make_gzip_layer(
            {f"etc/variant-{variant}": f"{variant}-{marker}\n".encode()}
        )
        top_desc = {
            **write_blob(top_gz),
            "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
        }
        config_obj = {
            "created": "1970-01-01T00:00:01Z",
            "architecture": "amd64",
            "os": "linux",
            "config": {
                "User": "vscode",
                "WorkingDir": "/workspaces",
                "Env": ["PATH=/usr/bin"],
            },
            "rootfs": {
                "type": "layers",
                "diff_ids": [shared_diff, top_diff],
            },
            "history": [
                {"created": "1970-01-01T00:00:01Z", "created_by": "shared"},
                {"created": "1970-01-01T00:00:01Z", "created_by": variant},
            ],
        }
        cfg_raw = (json.dumps(config_obj, sort_keys=True) + "\n").encode("utf-8")
        cfg_desc = {
            **write_blob(cfg_raw),
            "mediaType": "application/vnd.oci.image.config.v1+json",
        }
        manifest_obj = {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": cfg_desc,
            "layers": [shared_desc, top_desc],
        }
        manifest_raw = (json.dumps(manifest_obj, sort_keys=True) + "\n").encode("utf-8")
        m_desc = {
            **write_blob(manifest_raw),
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "annotations": {"org.opencontainers.image.ref.name": variant},
        }
        manifests_index.append(m_desc)
        variant_digests[variant] = str(m_desc["digest"])

    (dest / "index.json").write_text(
        json.dumps({"schemaVersion": 2, "manifests": manifests_index}, indent=2) + "\n",
        encoding="utf-8",
    )
    return variant_digests


@contextmanager
def local_oci_registry(work_dir: Path, *, htpasswd_line: str | None = None):
    registry_bin = shutil.which("registry")
    if not registry_bin:
        raise RuntimeError("Missing 'registry' binary (docker-distribution) in PATH")
    port = find_free_port()
    storage_dir = work_dir / "registry-data"
    storage_dir.mkdir(parents=True, exist_ok=True)
    cfg_lines = [
        "version: 0.1",
        "log:",
        "  level: warn",
        "storage:",
        "  filesystem:",
        f"    rootdirectory: {json.dumps(str(storage_dir))}",
        "  delete:",
        "    enabled: true",
        "http:",
        f"  addr: 127.0.0.1:{port}",
    ]
    if htpasswd_line is not None:
        htpasswd_path = work_dir / "htpasswd"
        htpasswd_path.write_text(htpasswd_line + "\n", encoding="utf-8")
        cfg_lines.extend(
            [
                "auth:",
                "  htpasswd:",
                "    realm: Registry",
                f"    path: {json.dumps(str(htpasswd_path))}",
            ]
        )
    cfg_lines.append("")
    cfg_path = work_dir / "registry-config.yml"
    cfg_path.write_text("\n".join(cfg_lines), encoding="utf-8")
    log_path = work_dir / "registry.log"
    with log_path.open("wb") as log_handle:
        proc = subprocess.Popen(
            [registry_bin, "serve", str(cfg_path)],
            stdout=log_handle,
            stderr=log_handle,
        )
        try:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                if proc.poll() is not None:
                    raise RuntimeError(
                        f"registry exited early ({proc.returncode}): {log_path.read_text(errors='replace')}"
                    )
                try:
                    with urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/v2/", timeout=1
                    ) as resp:
                        if resp.status == 200:
                            break
                except urllib.error.HTTPError as err:
                    if htpasswd_line is not None and err.code == 401:
                        break
                    time.sleep(0.1)
                except OSError:
                    time.sleep(0.1)
            else:
                raise RuntimeError("Timed out waiting for local distribution registry")
            yield f"127.0.0.1:{port}"
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)


def skopeo_raw_digest(image_ref: str) -> str:
    raw = subprocess.check_output(
        [
            "skopeo",
            "--insecure-policy",
            "inspect",
            "--raw",
            "--tls-verify=false",
            f"docker://{image_ref}",
        ],
        timeout=60,
    )
    return sha256_bytes(raw)


def git_cmd(cwd: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=cwd, text=True, timeout=30
    ).strip()


def commit_synthetic(repo: Path, filename: str, content: str, message: str) -> str:
    (repo / filename).write_text(content, encoding="utf-8")
    git_cmd(repo, "add", "--", filename)
    git_cmd(
        repo,
        "-c",
        "user.name=Publish Test",
        "-c",
        "user.email=test@example.invalid",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "--no-gpg-sign",
        "--quiet",
        "-m",
        message,
    )
    return git_cmd(repo, "rev-parse", "HEAD")


def run_publish_cli(args: list[str], *, env: dict[str, str] | None = None) -> dict:
    out = subprocess.check_output(
        [sys.executable, str(PUBLISH_PY), *args],
        env=env,
        text=True,
        timeout=120,
    ).strip()
    return json.loads(out)


def verify_publish_state_machine(work_dir: Path, real_oci_dir: Path | None) -> None:
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import publish as publish_mod

    if real_oci_dir is not None:
        real_digests = publish_mod.parse_local_oci_digests(real_oci_dir.resolve())
        assert set(real_digests) == {"latest", "agent"}, real_digests

    oci_v1 = work_dir / "oci-v1"
    oci_v2 = work_dir / "oci-v2"
    digests_v1 = build_synthetic_oci_layout(oci_v1, marker="v1")
    digests_v2 = build_synthetic_oci_layout(oci_v2, marker="v2")
    assert digests_v1["latest"] != digests_v2["latest"]

    bare_remote = work_dir / "upstream.git"
    clone_dir = work_dir / "clone"
    bare_remote.mkdir()
    clone_dir.mkdir()
    git_cmd(bare_remote, "init", "--bare", "--quiet", "--initial-branch=master")
    git_cmd(clone_dir, "init", "--quiet", "--initial-branch=master")
    git_cmd(clone_dir, "remote", "add", "origin", str(bare_remote))

    sha1 = commit_synthetic(clone_dir, "rev.txt", "1\n", "commit 1")
    git_cmd(clone_dir, "push", "--quiet", "origin", "master")

    with local_oci_registry(work_dir) as registry_addr:
        repo_name = "hellodword/devcontainers-dev"
        summary_md = work_dir / "summary-1.md"

        # 1. Initial 4-tag publish & exact digest preservation.
        res1 = run_publish_cli(
            [
                "--oci-dir",
                str(oci_v1),
                "--registry",
                registry_addr,
                "--repository",
                repo_name,
                "--commit-sha",
                sha1,
                "--git-remote",
                str(bare_remote),
                "--flake-lock",
                str(REPO_ROOT / "flake.lock"),
                "--action-sha",
                "a" * 40,
                "--tls-verify",
                "false",
            ],
            env=os.environ | {"GITHUB_STEP_SUMMARY": str(summary_md)},
        )
        assert len(res1["coreSha"]) == 40, res1
        assert res1["actionSha"] == "a" * 40, res1
        for tag in (f"sha-{sha1}", "latest"):
            assert res1["tags"][tag]["status"] == "published", res1
            assert (
                skopeo_raw_digest(f"{registry_addr}/{repo_name}:{tag}")
                == digests_v1["latest"]
            )
        for tag in (f"agent-sha-{sha1}", "agent"):
            assert res1["tags"][tag]["status"] == "published", res1
            assert (
                skopeo_raw_digest(f"{registry_addr}/{repo_name}:{tag}")
                == digests_v1["agent"]
            )
        summary_text = summary_md.read_text(encoding="utf-8")
        assert (
            f"docker pull {registry_addr}/{repo_name}@{digests_v1['latest']}"
            in summary_text
        )
        assert res1["coreSha"] in summary_text

        # 2. Idempotent rerun on same commit -> immutable tags reused, digests unchanged.
        res2 = run_publish_cli(
            [
                "--oci-dir",
                str(oci_v1),
                "--registry",
                registry_addr,
                "--repository",
                repo_name,
                "--commit-sha",
                sha1,
                "--git-remote",
                str(bare_remote),
                "--flake-lock",
                str(REPO_ROOT / "flake.lock"),
                "--tls-verify",
                "false",
            ]
        )
        assert res2["tags"][f"sha-{sha1}"]["status"] == "reused", res2
        assert res2["tags"][f"agent-sha-{sha1}"]["status"] == "reused", res2
        assert res2["tags"]["latest"]["status"] == "published", res2
        assert res2["tags"]["agent"]["status"] == "published", res2

        # 3. Interrupted release recovery: pre-seed only sha-<sha1>, agent-sha-<sha1>, and :latest.
        recovery_repo = "hellodword/devcontainers-recovery"
        for variant, pre_tag in (
            ("latest", f"sha-{sha1}"),
            ("agent", f"agent-sha-{sha1}"),
            ("latest", "latest"),
        ):
            subprocess.run(
                [
                    "skopeo",
                    "--insecure-policy",
                    "copy",
                    "--preserve-digests",
                    "--dest-tls-verify=false",
                    f"oci:{oci_v1}:{variant}",
                    f"docker://{registry_addr}/{recovery_repo}:{pre_tag}",
                ],
                check=True,
                timeout=60,
            )
        res_rec = run_publish_cli(
            [
                "--oci-dir",
                str(oci_v1),
                "--registry",
                registry_addr,
                "--repository",
                recovery_repo,
                "--commit-sha",
                sha1,
                "--git-remote",
                str(bare_remote),
                "--flake-lock",
                str(REPO_ROOT / "flake.lock"),
                "--tls-verify",
                "false",
            ]
        )
        assert res_rec["tags"][f"sha-{sha1}"]["status"] == "reused", res_rec
        assert res_rec["tags"][f"agent-sha-{sha1}"]["status"] == "reused", res_rec
        assert res_rec["tags"]["agent"]["status"] == "published", res_rec
        assert (
            skopeo_raw_digest(f"{registry_addr}/{recovery_repo}:agent")
            == digests_v1["agent"]
        )

        # 4. Digest conflict protection: pre-seed sha-<sha2> with v1 digest, attempt to publish v2 -> abort!
        sha2 = commit_synthetic(clone_dir, "rev.txt", "2\n", "commit 2")
        git_cmd(clone_dir, "push", "--quiet", "origin", "master")
        subprocess.run(
            [
                "skopeo",
                "--insecure-policy",
                "copy",
                "--preserve-digests",
                "--dest-tls-verify=false",
                f"oci:{oci_v1}:latest",
                f"docker://{registry_addr}/{repo_name}:sha-{sha2}",
            ],
            check=True,
            timeout=60,
        )
        conflict = subprocess.run(
            [
                sys.executable,
                str(PUBLISH_PY),
                "--oci-dir",
                str(oci_v2),
                "--registry",
                registry_addr,
                "--repository",
                repo_name,
                "--commit-sha",
                sha2,
                "--git-remote",
                str(bare_remote),
                "--flake-lock",
                str(REPO_ROOT / "flake.lock"),
                "--tls-verify",
                "false",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=120,
        )
        assert conflict.returncode != 0, (
            "Expected non-zero exit on immutable tag digest conflict"
        )
        assert "Digest conflict" in conflict.stderr, conflict.stderr
        assert (
            skopeo_raw_digest(f"{registry_addr}/{repo_name}:sha-{sha2}")
            == digests_v1["latest"]
        )

        # 5a. Remote master already advanced -> publish sha-* for older commit, skip floating :latest & :agent.
        sha_old = commit_synthetic(clone_dir, "rev.txt", "3-old\n", "commit 3 old")
        sha_new = commit_synthetic(clone_dir, "rev.txt", "4-new\n", "commit 4 new")
        git_cmd(clone_dir, "push", "--quiet", "origin", "master")
        assert git_cmd(bare_remote, "rev-parse", "refs/heads/master") == sha_new

        res_stale = run_publish_cli(
            [
                "--oci-dir",
                str(oci_v2),
                "--registry",
                registry_addr,
                "--repository",
                repo_name,
                "--commit-sha",
                sha_old,
                "--git-remote",
                str(bare_remote),
                "--flake-lock",
                str(REPO_ROOT / "flake.lock"),
                "--tls-verify",
                "false",
            ]
        )
        assert res_stale["tags"][f"sha-{sha_old}"]["status"] == "published", res_stale
        assert res_stale["tags"][f"agent-sha-{sha_old}"]["status"] == "published", (
            res_stale
        )
        assert res_stale["tags"]["latest"]["status"] == "skipped", res_stale
        assert res_stale["tags"]["agent"]["status"] == "skipped", res_stale
        assert (
            skopeo_raw_digest(f"{registry_addr}/{repo_name}:latest")
            == digests_v1["latest"]
        )
        assert (
            skopeo_raw_digest(f"{registry_addr}/{repo_name}:agent")
            == digests_v1["agent"]
        )

        # 5b. Mid-flight master advancement right after :latest before :agent -> :agent skipped!
        sha_mid_next = commit_synthetic(
            clone_dir, "rev.txt", "5-next\n", "commit 5 next"
        )
        real_query = publish_mod.query_remote_branch_sha
        call_count = 0

        def advance_after_first_check(git_remote: str, expected_ref: str) -> str:
            nonlocal call_count
            call_count += 1
            if call_count == 2:
                git_cmd(
                    clone_dir,
                    "push",
                    "--quiet",
                    "origin",
                    f"{sha_mid_next}:refs/heads/master",
                )
            return real_query(git_remote, expected_ref)

        captured_mid = io.StringIO()
        with (
            patch.object(
                publish_mod,
                "query_remote_branch_sha",
                side_effect=advance_after_first_check,
            ),
            redirect_stdout(captured_mid),
        ):
            rc_mid = publish_mod.main(
                [
                    "--oci-dir",
                    str(oci_v2),
                    "--registry",
                    registry_addr,
                    "--repository",
                    repo_name,
                    "--commit-sha",
                    sha_new,
                    "--git-remote",
                    str(bare_remote),
                    "--flake-lock",
                    str(REPO_ROOT / "flake.lock"),
                    "--tls-verify",
                    "false",
                ]
            )
        assert rc_mid == 0, rc_mid
        res_mid = json.loads(captured_mid.getvalue())
        assert res_mid["tags"]["latest"]["status"] == "published", res_mid
        assert res_mid["tags"]["agent"]["status"] == "skipped", res_mid
        assert (
            skopeo_raw_digest(f"{registry_addr}/{repo_name}:latest")
            == digests_v2["latest"]
        )
        assert (
            skopeo_raw_digest(f"{registry_addr}/{repo_name}:agent")
            == digests_v1["agent"]
        )


def verify_authenticated_skopeo_login_and_publish(work_dir: Path) -> None:
    htpasswd_entry = (
        "ci-actor:$2b$05$7/jFoEubo.eVjJ8ADU10iOl5dFwtfGLFyR0vBDf5km9KoEUVdGJ42"
    )
    oci_auth = work_dir / "oci-auth"
    digests = build_synthetic_oci_layout(oci_auth, marker="auth-v1")

    bare_remote = work_dir / "auth-upstream.git"
    clone_dir = work_dir / "auth-clone"
    bare_remote.mkdir()
    clone_dir.mkdir()
    git_cmd(bare_remote, "init", "--bare", "--quiet", "--initial-branch=master")
    git_cmd(clone_dir, "init", "--quiet", "--initial-branch=master")
    git_cmd(clone_dir, "remote", "add", "origin", str(bare_remote))
    sha = commit_synthetic(clone_dir, "rev.txt", "auth\n", "auth commit")
    git_cmd(clone_dir, "push", "--quiet", "origin", "master")

    with local_oci_registry(
        work_dir / "auth-reg", htpasswd_line=htpasswd_entry
    ) as auth_reg:
        unauth_res = subprocess.run(
            [
                sys.executable,
                str(PUBLISH_PY),
                "--oci-dir",
                str(oci_auth),
                "--registry",
                auth_reg,
                "--repository",
                "hellodword/devcontainers-dev",
                "--commit-sha",
                sha,
                "--expected-master-ref",
                "refs/heads/master",
                "--git-remote",
                str(bare_remote),
                "--tls-verify",
                "false",
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        assert unauth_res.returncode != 0, (
            "Unauthenticated publish unexpectedly succeeded"
        )

        login_publish_script = f"""
        set -euo pipefail
        umask 077
        authdir="$(mktemp -d {json.dumps(str(work_dir))}/ghcr-auth.XXXXXX)"
        trap 'rm -rf "$authdir"' EXIT
        authfile="$authdir/auth.json"
        printf '%s' 'ci-secret-token' | skopeo login {json.dumps(auth_reg)} \
          --tls-verify=false \
          --username ci-actor \
          --password-stdin \
          --authfile "$authfile"
        test "$(stat -c '%a' "$authfile")" = "600"
        {json.dumps(sys.executable)} {json.dumps(str(PUBLISH_PY))} \
          --oci-dir {json.dumps(str(oci_auth))} \
          --registry {json.dumps(auth_reg)} \
          --repository hellodword/devcontainers-dev \
          --commit-sha {json.dumps(sha)} \
          --expected-master-ref refs/heads/master \
          --git-remote {json.dumps(str(bare_remote))} \
          --tls-verify false \
          --authfile "$authfile"
        """
        auth_proc = subprocess.run(
            ["bash", "-euo", "pipefail", "-c", login_publish_script],
            check=True,
            capture_output=True,
            text=True,
        )
        receipt = json.loads(auth_proc.stdout.strip().splitlines()[-1])
        assert receipt["tags"]["latest"]["digest"] == digests["latest"], receipt
        assert receipt["tags"]["agent"]["digest"] == digests["agent"], receipt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--oci-dir",
        type=Path,
        default=None,
        help="Optional built packages.oci directory to cross-check index.json digests",
    )
    args = parser.parse_args(argv)

    with tempfile.TemporaryDirectory(prefix="devcontainers-check-publish-") as tmp:
        work_dir = Path(tmp)
        verify_publish_state_machine(work_dir, args.oci_dir)
        verify_authenticated_skopeo_login_and_publish(work_dir)

    print("CHECK_PUBLISH_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
