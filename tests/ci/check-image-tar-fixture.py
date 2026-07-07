#!/usr/bin/env python3
"""Synthetic self-test for the image artifact validator.

Real generated images mostly exercise the success path. This fixture checks
that valid OCI image JSON is accepted and that an oversized layer is rejected,
without changing the artifact checker or depending on a full image build.
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def env_map(entries: list[str]) -> dict[str, str]:
    return dict(entry.split("=", 1) for entry in entries)


SOURCE_VERSION = {
    "version": "fixture-rev-dirty",
    "revision": "fixture-revision-dirty",
    "shortRevision": "fixture-rev-dirty",
    "dirty": True,
    "lastModified": 1,
}


def write_expected_reports(reports_dir: Path, env_entries: list[str]) -> None:
    write_json(
        reports_dir / "image-plan.json",
        {
            "image": "fixture",
            "user": "vscode",
            "workingDir": "/workspaces",
            "entrypoint": ["/usr/bin/devcontainer-entrypoint"],
            "sourceVersion": SOURCE_VERSION,
        },
    )
    write_json(
        reports_dir / "ci-plan.json",
        {
            "image": "fixture",
            "architectures": ["linux/amd64"],
            "sourceVersion": SOURCE_VERSION,
            "reportFiles": [],
        },
    )
    write_json(reports_dir / "env-report.json", {"containerEnv": env_map(env_entries)})
    write_json(reports_dir / "metadata-label.json", [])
    write_json(reports_dir / "version.json", SOURCE_VERSION)


def layer_budget(max_layer_size: str = "8GiB", max_layers: int = 100, reserve: int = 20) -> dict:
    return {
        "strategy": "balanced",
        "max": max_layers,
        "reserve": reserve,
        "semanticMax": max_layers - reserve,
        "maxLayerSize": max_layer_size,
    }


def write_layer_reports(
    reports_dir: Path,
    max_layer_size: str = "8GiB",
    groups: list[str] | None = None,
    max_layers: int = 100,
    reserve: int = 20,
) -> None:
    groups = groups or []
    budget = layer_budget(max_layer_size, max_layers, reserve)
    write_json(
        reports_dir / "layer-plan.json",
        {
            "budget": budget,
            "order": groups,
            "layers": [{"group": group} for group in groups],
        },
    )
    write_json(
        reports_dir / "layer-closure-report.json",
        {
            "budget": budget,
            "order": groups,
            "layers": [
                {
                    "group": group,
                    "rootPathCount": 0,
                    "closurePathCount": 0,
                    "closureSizeBytes": 0,
                    "closureStorePaths": [],
                }
                for group in groups
            ],
        },
    )


def semantic_layer(group: str, size: int = 2048) -> dict:
    return {
        "digest": f"sha256:{group}",
        "size": size,
        "diff_ids": f"sha256:{group}",
        "mediatype": "application/vnd.oci.image.layer.v1.tar",
        "History": {"created_by": f"devcontainers.nix semantic layer {group}"},
    }


def main() -> int:
    repo_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        reports_dir = tmpdir / "reports"
        reports_dir.mkdir()
        image_path = tmpdir / "image.json"
        env_entries = [
            "HOME=/home/vscode",
            "XDG_CONFIG_HOME=/home/vscode/.config",
            "XDG_CACHE_HOME=/home/vscode/.cache",
            "XDG_DATA_HOME=/home/vscode/.local/share",
            "XDG_STATE_HOME=/home/vscode/.local/state",
            "XDG_RUNTIME_DIR=/run/user/1000",
            "LANG=en_US.UTF-8",
            "LANGUAGE=en_US:en",
            "LOCALE_ARCHIVE=/nix/store/fixture-glibc-locales/lib/locale/locale-archive",
            "XDG_CONFIG_DIRS=/etc/xdg",
            "XDG_DATA_DIRS=/usr/local/share:/usr/share",
            "NIXPKGS_CONFIG=/etc/nixpkgs/config.nix",
            "NIXPKGS_ALLOW_UNFREE=1",
            "NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1",
            "NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1",
            "DEVPKG_NIXPKGS_REF=path:/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source",
            "DEVPKG_NIXPKGS_CACHE_KEY=fixture-rev",
            "DEVPKG_SYSTEM=x86_64-linux",
            "DEVCONTAINERS_NIX_VERSION=fixture-rev-dirty",
            "DEVCONTAINERS_NIX_REVISION=fixture-revision-dirty",
            "DEVCONTAINERS_NIX_DIRTY=true",
            "DEVCONTAINERS_NIX_VERSION_FILE=/usr/share/devcontainer/version.json",
            "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
            "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
            "CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt",
            "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt",
            "TZDIR=/etc/zoneinfo",
        ]
        write_json(
            image_path,
            {
                "version": 1,
                "arch": "amd64",
                "image-config": {
                    "User": "vscode",
                    "WorkingDir": "/workspaces",
                    "Entrypoint": ["/usr/bin/devcontainer-entrypoint"],
                    "Env": env_entries,
                    "Labels": {
                        "devcontainer.metadata": "[]",
                        "devcontainers.nix.dirty": "true",
                        "devcontainers.nix.revision": "fixture-revision-dirty",
                        "devcontainers.nix.version": "fixture-rev-dirty",
                        "org.opencontainers.image.revision": "fixture-revision-dirty",
                        "org.opencontainers.image.version": "fixture-rev-dirty",
                    },
                },
                "layers": [
                    {
                        "digest": "sha256:fixture",
                        "size": 2048,
                        "diff_ids": "sha256:fixture",
                        "mediatype": "application/vnd.oci.image.layer.v1.tar",
                        "History": {"created_by": "fixture layer"},
                    }
                ],
            },
        )

        checker = repo_root / "tests" / "ci" / "check-image-tar.py"
        budget_checker = repo_root / "tests" / "ci" / "check-layer-budget.py"
        write_expected_reports(reports_dir, env_entries)
        write_layer_reports(reports_dir, "8GiB")
        passing = subprocess.run(
            [
                sys.executable,
                str(checker),
                str(image_path),
                str(reports_dir),
                "fixture",
                "path:/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        if "image-artifact-check ok: fixture" not in passing.stdout:
            fail("expected image artifact checker to pass fixture")

        write_layer_reports(reports_dir, "1KiB")
        failing = subprocess.run(
            [
                sys.executable,
                str(checker),
                str(image_path),
                str(reports_dir),
                "fixture",
                "path:/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if failing.returncode == 0 or "exceeds max layer size 1024 B" not in failing.stderr:
            fail("expected oversized layer validation to fail")

        write_json(image_path, {"layers": [{"size": 1}, {"size": 1}]})
        write_layer_reports(reports_dir, "8GiB", max_layers=1, reserve=0)
        too_many_layers = subprocess.run(
            [sys.executable, str(budget_checker), str(image_path), str(reports_dir), "fixture"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if too_many_layers.returncode == 0 or "image layer count 2 exceeds budget 1" not in too_many_layers.stderr:
            fail("expected total layer count validation to fail")

        write_json(image_path, {"layers": [semantic_layer("one"), semantic_layer("two")]})
        write_layer_reports(reports_dir, "8GiB", groups=["one", "two"], max_layers=2, reserve=1)
        too_many_semantic_layers = subprocess.run(
            [sys.executable, str(budget_checker), str(image_path), str(reports_dir), "fixture"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if (
            too_many_semantic_layers.returncode == 0
            or "semantic layer count 2 exceeds budget 1" not in too_many_semantic_layers.stderr
        ):
            fail("expected semantic layer count validation to fail")

        write_json(image_path, {"layers": [semantic_layer("two")]})
        write_layer_reports(reports_dir, "8GiB", groups=["one"], max_layers=10, reserve=0)
        mismatched_groups = subprocess.run(
            [sys.executable, str(budget_checker), str(image_path), str(reports_dir), "fixture"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if (
            mismatched_groups.returncode == 0
            or "image semantic layer groups do not match layer-plan.json order" not in mismatched_groups.stderr
        ):
            fail("expected semantic layer group validation to fail")

    print("image-tar-fixture ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
