#!/usr/bin/env python3
"""Verification entrypoint (`nix run .#verify`): static checks, OCI layout, release state machine, and VM suites."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

SANITIZED_NIXPKGS_VARS = (
    "NIXPKGS_ALLOW_BROKEN",
    "NIXPKGS_ALLOW_INSECURE",
    "NIXPKGS_ALLOW_UNFREE",
    "NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM",
)


@contextmanager
def sanitized_nixpkgs_env():
    """Run impure flake/manifest evaluation with an empty nixpkgs user config matching clean CI."""
    with tempfile.TemporaryDirectory(prefix="devcontainers-nixpkgs-cfg-") as cfg_dir:
        empty_cfg = Path(cfg_dir) / "config.nix"
        empty_cfg.write_text("{}\n", encoding="utf-8")
        env = dict(os.environ)
        for key in SANITIZED_NIXPKGS_VARS:
            env.pop(key, None)
        env["NIXPKGS_CONFIG"] = str(empty_cfg)
        yield env


def log_step(title: str) -> None:
    print(f"\n==> {title}", flush=True)


def run_checked(
    cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None
) -> None:
    print("  $", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def capture_checked(
    cmd: list[str], *, cwd: Path, env: dict[str, str] | None = None
) -> str:
    print("  $", " ".join(cmd), flush=True)
    return subprocess.check_output(cmd, cwd=cwd, env=env, text=True).strip()


def resolve_project_dir(explicit: Path | None) -> Path:
    if explicit is not None:
        candidate = explicit.resolve()
    else:
        cwd = Path.cwd().resolve()
        if (cwd / "flake.nix").is_file() and (cwd / "tests" / "verify.py").is_file():
            candidate = cwd
        else:
            top = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                cwd=cwd,
                capture_output=True,
                text=True,
                check=False,
            )
            if top.returncode != 0 or not top.stdout.strip():
                print(
                    "error: must run inside a devcontainers.nix Git checkout or pass --project-dir <git-checkout>",
                    file=sys.stderr,
                )
                raise SystemExit(2)
            candidate = Path(top.stdout.strip()).resolve()

    if (
        not (candidate / "flake.nix").is_file()
        or not (candidate / "tests" / "verify.py").is_file()
    ):
        print(
            f"error: {candidate} is not a devcontainers.nix repository root",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if not (candidate / ".git").exists():
        print(
            f"error: {candidate} lacks .git metadata; pass --project-dir <git-checkout> instead of verifying an unversioned store copy",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return candidate


def verify_clean_oci_revision(project_dir: Path, oci_out: Path) -> None:
    status = subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=project_dir, text=True
    ).strip()
    if status:
        return
    head_sha = capture_checked(["git", "rev-parse", "HEAD"], cwd=project_dir)
    index = json.loads((oci_out / "index.json").read_text(encoding="utf-8"))
    for desc in index.get("manifests") or []:
        ref_name = (desc.get("annotations") or {}).get(
            "org.opencontainers.image.ref.name"
        )
        if ref_name not in {"latest", "agent"}:
            continue
        manifest_blob = oci_out / "blobs" / "sha256" / desc["digest"].split(":", 1)[1]
        manifest = json.loads(manifest_blob.read_text(encoding="utf-8"))
        cfg_blob = (
            oci_out / "blobs" / "sha256" / manifest["config"]["digest"].split(":", 1)[1]
        )
        cfg = json.loads(cfg_blob.read_text(encoding="utf-8"))
        labels = (cfg.get("config") or {}).get("Labels") or {}
        if labels.get("org.opencontainers.image.revision") != head_sha:
            raise RuntimeError(
                f"OCI variant {ref_name} revision label {labels.get('org.opencontainers.image.revision')!r} != HEAD {head_sha!r}"
            )
        if labels.get("devcontainers.nix.dirty") != "false":
            raise RuntimeError(
                f"OCI variant {ref_name} marked dirty on clean checkout: {labels.get('devcontainers.nix.dirty')!r}"
            )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-dir",
        type=Path,
        default=None,
        help="Git checkout root directory (defaults to enclosing Git repository root)",
    )
    args = parser.parse_args(argv)
    project_dir = resolve_project_dir(args.project_dir)

    log_step("1. Evaluating flake outputs, formatting, and lint checks")
    run_checked(
        ["nix", "flake", "check", "--no-build", "--no-update-lock-file"],
        cwd=project_dir,
    )
    run_checked(
        [
            "nix",
            "build",
            "--no-link",
            "--no-update-lock-file",
            ".#checks.x86_64-linux.formatting",
            ".#checks.x86_64-linux.lint",
        ],
        cwd=project_dir,
    )

    log_step("2. Evaluating CI manifest under clean nixpkgs environment")
    nix_ci = shutil.which("nix-ci")
    if not nix_ci:
        raise RuntimeError("nix-ci binary not found in PATH")
    with (
        sanitized_nixpkgs_env() as clean_env,
        tempfile.TemporaryDirectory(prefix="devcontainers-verify-ci-") as ci_state,
    ):
        run_checked(
            [
                nix_ci,
                "evaluate",
                "--project-dir",
                str(project_dir),
                "--state",
                ci_state,
            ],
            cwd=project_dir,
            env=clean_env,
        )

    log_step("3. Building shared packages.oci and verifying OCI layout invariants")
    oci_out = capture_checked(
        [
            "nix",
            "build",
            "--no-link",
            "--print-out-paths",
            "--no-update-lock-file",
            ".#oci",
        ],
        cwd=project_dir,
    )
    verify_clean_oci_revision(project_dir, Path(oci_out))

    log_step("4. Running Workflow 3: digest-preserving release and recovery tests")
    run_checked(
        [
            sys.executable,
            str(project_dir / "tests" / "check_publish.py"),
            "--oci-dir",
            oci_out,
        ],
        cwd=project_dir,
    )

    log_step("5. Running Workflow 1 (vm-containers) and Workflow 2 (vm-editor)")
    vm_attrs = ("vm-containers", "vm-editor")
    run_checked(
        [
            "nix",
            "build",
            "--no-link",
            "--no-update-lock-file",
            *[f".#checks.x86_64-linux.{name}.driver" for name in vm_attrs],
        ],
        cwd=project_dir,
    )
    if not os.access("/dev/kvm", os.R_OK | os.W_OK):
        raise RuntimeError(
            "KVM is unavailable (/dev/kvm not accessible); run on a KVM host or submit "
            ".#checks.x86_64-linux.vm-{containers,editor} via vm-test-submit."
        )
    for name in vm_attrs:
        run_checked(
            [
                "nix",
                "build",
                "--no-link",
                "--print-build-logs",
                "--no-update-lock-file",
                f".#checks.x86_64-linux.{name}",
            ],
            cwd=project_dir,
        )

    print("\nVERIFY_ALL_PASSED", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
