#!/usr/bin/env python3
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


def write_layer_plan(reports_dir: Path, max_layer_size: str) -> None:
    write_json(
        reports_dir / "layer-plan.json",
        {
            "budget": {
                "strategy": "balanced",
                "max": 100,
                "reserve": 20,
                "maxLayerSize": max_layer_size,
            },
            "layers": [],
        },
    )


def main() -> int:
    repo_root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        reports_dir = tmpdir / "reports"
        reports_dir.mkdir()
        image_path = tmpdir / "image.json"
        write_json(
            image_path,
            {
                "version": 1,
                "arch": "amd64",
                "image-config": {
                    "User": "vscode",
                    "WorkingDir": "/workspaces",
                    "Entrypoint": ["/usr/bin/devcontainer-entrypoint"],
                    "Env": [
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
                        "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
                        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
                        "CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt",
                        "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt",
                        "TZDIR=/etc/zoneinfo",
                    ],
                    "Labels": {"devcontainer.metadata": "[]"},
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
        write_layer_plan(reports_dir, "8GiB")
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

        write_layer_plan(reports_dir, "1KiB")
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

    print("image-tar-fixture ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
