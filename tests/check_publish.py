#!/usr/bin/env python3
"""Workflow 3 verification: digest-preserving OCI release, conflict protection, and recovery."""

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
from contextlib import contextmanager
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


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

    base_gz, base_diff = make_gzip_layer(
        {"nix/store/base": f"base-{marker}\n".encode()}
    )
    base_desc = {
        **write_blob(base_gz),
        "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
    }

    top_gz, top_diff = make_gzip_layer(
        {"etc/release-marker": f"latest-{marker}\n".encode()}
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
            "diff_ids": [base_diff, top_diff],
        },
        "history": [
            {"created": "1970-01-01T00:00:01Z", "created_by": "base"},
            {"created": "1970-01-01T00:00:01Z", "created_by": "latest"},
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
        "layers": [base_desc, top_desc],
    }
    manifest_raw = (json.dumps(manifest_obj, sort_keys=True) + "\n").encode("utf-8")
    m_desc = {
        **write_blob(manifest_raw),
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "annotations": {"org.opencontainers.image.ref.name": "latest"},
    }

    (dest / "index.json").write_text(
        json.dumps({"schemaVersion": 2, "manifests": [m_desc]}, indent=2) + "\n",
        encoding="utf-8",
    )
    return {"latest": str(m_desc["digest"])}


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


def run_publish_cli(
    publish_bin: Path, args: list[str], *, env: dict[str, str] | None = None
) -> dict:
    out = subprocess.check_output(
        [str(publish_bin), *args],
        env=env,
        text=True,
        timeout=120,
    ).strip()
    return json.loads(out)


def verify_publish_state_machine(
    work_dir: Path, publish_bin: Path, real_oci_dir: Path | None
) -> None:
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import publish as publish_mod

    if real_oci_dir is not None:
        real_digests = publish_mod.parse_local_oci_digests(real_oci_dir.resolve())
        assert set(real_digests) == {"latest"}, real_digests

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

        # 1. Initial publish & exact digest preservation across :sha-<commit> and :latest.
        res1 = run_publish_cli(
            publish_bin,
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
        summary_text = summary_md.read_text(encoding="utf-8")
        assert (
            f"docker pull {registry_addr}/{repo_name}@{digests_v1['latest']}"
            in summary_text
        )
        assert res1["coreSha"] in summary_text

        # 2. Idempotent rerun on same commit -> immutable tag reused, digest unchanged.
        res2 = run_publish_cli(
            publish_bin,
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
            ],
        )
        assert res2["tags"][f"sha-{sha1}"]["status"] == "reused", res2
        assert res2["tags"]["latest"]["status"] == "published", res2

        # 3. Interrupted release recovery: pre-seed only sha-<sha1>, rerun completes :latest.
        recovery_repo = "hellodword/devcontainers-recovery"
        subprocess.run(
            [
                "skopeo",
                "--insecure-policy",
                "copy",
                "--preserve-digests",
                "--dest-tls-verify=false",
                f"oci:{oci_v1}:latest",
                f"docker://{registry_addr}/{recovery_repo}:sha-{sha1}",
            ],
            check=True,
            timeout=60,
        )
        res_rec = run_publish_cli(
            publish_bin,
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
            ],
        )
        assert res_rec["tags"][f"sha-{sha1}"]["status"] == "reused", res_rec
        assert res_rec["tags"]["latest"]["status"] == "published", res_rec
        assert (
            skopeo_raw_digest(f"{registry_addr}/{recovery_repo}:latest")
            == digests_v1["latest"]
        )

        # 4. Digest conflict protection: pre-seed sha-<sha2> with v1 digest, attempt to publish v2 -> abort.
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
                str(publish_bin),
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

        # 5. Remote master already advanced -> publish sha-<sha_old>, skip floating :latest.
        sha_old = commit_synthetic(clone_dir, "rev.txt", "3-old\n", "commit 3 old")
        sha_new = commit_synthetic(clone_dir, "rev.txt", "4-new\n", "commit 4 new")
        git_cmd(clone_dir, "push", "--quiet", "origin", "master")
        assert git_cmd(bare_remote, "rev-parse", "refs/heads/master") == sha_new

        res_stale = run_publish_cli(
            publish_bin,
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
            ],
        )
        assert res_stale["tags"][f"sha-{sha_old}"]["status"] == "published", res_stale
        assert res_stale["tags"]["latest"]["status"] == "skipped", res_stale
        assert (
            skopeo_raw_digest(f"{registry_addr}/{repo_name}:latest")
            == digests_v1["latest"]
        )


def verify_authenticated_skopeo_login_and_publish(
    work_dir: Path, publish_bin: Path
) -> None:
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
                str(publish_bin),
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

        manifest_file = work_dir / "manifest.json"
        manifest_file.write_text(
            json.dumps(
                {
                    "groups": [
                        {
                            "name": "build",
                            "entries": [{"name": "oci", "outputs": [str(oci_auth)]}],
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        auth_env = os.environ | {
            "GHCR_ACTOR": "ci-actor",
            "GHCR_TOKEN": "ci-secret-token",
        }
        preflight_proc = subprocess.run(
            [
                str(publish_bin),
                "--registry",
                auth_reg,
                "--tls-verify",
                "false",
                "--login-env",
                "--preflight-only",
            ],
            env=auth_env,
            check=True,
            capture_output=True,
            text=True,
        )
        assert json.loads(preflight_proc.stdout)["preflight"] == "ok", (
            preflight_proc.stdout
        )

        auth_proc = subprocess.run(
            [
                str(publish_bin),
                "--manifest",
                str(manifest_file),
                "--login-env",
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
            env=auth_env,
            check=True,
            capture_output=True,
            text=True,
        )
        receipt = json.loads(auth_proc.stdout.strip().splitlines()[-1])
        assert receipt["tags"]["latest"]["digest"] == digests["latest"], receipt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--publish-bin",
        type=Path,
        default=os.environ.get("DEVCONTAINERS_PUBLISH_BIN"),
        help="Path to the built publish-devcontainers executable",
    )
    parser.add_argument(
        "--oci-dir",
        type=Path,
        default=None,
        help="Optional built packages.oci directory to cross-check index.json digest",
    )
    args = parser.parse_args(argv)
    if args.publish_bin is None:
        parser.error("missing required --publish-bin path")
    if not args.publish_bin.is_file() or not os.access(args.publish_bin, os.X_OK):
        parser.error(f"--publish-bin is not an executable file: {args.publish_bin}")

    publish_bin = args.publish_bin.resolve()
    with tempfile.TemporaryDirectory(prefix="devcontainers-check-publish-") as tmp:
        work_dir = Path(tmp)
        verify_publish_state_machine(work_dir, publish_bin, args.oci_dir)
        verify_authenticated_skopeo_login_and_publish(work_dir, publish_bin)

    print("CHECK_PUBLISH_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
