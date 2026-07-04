#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys
import tempfile


def fail(message: str) -> None:
    print(f"rootfs-layout-fixture failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(value, handle)


def mkdir(rootfs: pathlib.Path, path: str) -> None:
    (rootfs / path.lstrip("/")).mkdir(parents=True, exist_ok=True)


def write_minimal_reports(rootfs: pathlib.Path, reports_dir: pathlib.Path) -> None:
    mkdir(rootfs, "/run/user/1000")
    mkdir(rootfs, "/usr/bin")
    write_json(rootfs / "usr/share/devcontainer/vscode/extensions-index.json", {
        "projectionTargets": [],
        "extensions": [],
    })
    write_json(reports_dir / "env-report.json", {
        "containerEnv": {
            "PATH": "/usr/local/bin:/usr/bin",
        },
        "environment": {
            "pathsToLink": [],
        },
    })
    write_json(reports_dir / "filesystem-report.json", {
        "directories": [
            {
                "path": "/run/user/1000",
                "owner": "vscode:vscode",
                "mode": "0700",
            },
        ],
        "shellFiles": [],
        "etcFiles": [],
        "symlinks": [],
        "vscodeMachineSettings": {
            "settings": {},
            "paths": [],
        },
    })
    write_json(reports_dir / "profile-report.json", {
        "provides": {
            "commands": [],
        },
        "vscode": {
            "settings": {},
        },
    })
    write_json(reports_dir / "extensions-report.json", {
        "artifacts": {
            "archiveEnabled": False,
        },
    })


def run_checker(checker: pathlib.Path, rootfs: pathlib.Path, reports_dir: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [
            sys.executable,
            str(checker),
            str(rootfs),
            str(reports_dir),
            "fixture",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def main() -> int:
    repo_root = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(".")
    checker = repo_root / "tests" / "ci" / "check-rootfs-layout.py"
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = pathlib.Path(tmp)
        rootfs = tmpdir / "rootfs"
        reports_dir = tmpdir / "reports"
        rootfs.mkdir()
        reports_dir.mkdir()
        write_minimal_reports(rootfs, reports_dir)

        missing_path_dir = run_checker(checker, rootfs, reports_dir)
        expected = "PATH contains directories missing from rootfs: /usr/local/bin"
        if missing_path_dir.returncode == 0 or expected not in missing_path_dir.stderr:
            fail("expected missing PATH directory validation to fail")

        mkdir(rootfs, "/usr/local/bin")
        passing = run_checker(checker, rootfs, reports_dir)
        if passing.returncode != 0:
            fail(f"expected rootfs layout checker to pass complete fixture: {passing.stderr}")

    print("rootfs-layout-fixture ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
