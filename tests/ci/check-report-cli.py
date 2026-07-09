#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def read_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def run_tool(tool: Path, args: list[str], *, env: dict[str, str] | None = None, check: bool = True):
    return subprocess.run(
        [str(tool / "bin" / "devcontainer-image"), *args],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


def run_json(tool: Path, args: list[str]):
    return json.loads(run_tool(tool, args).stdout)


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: tests/ci/check-report-cli.py <devcontainer-image> <reports-dir> <image-name>", file=sys.stderr)
        return 1
    tool = Path(sys.argv[1])
    reports_dir = Path(sys.argv[2])
    image_name = sys.argv[3]

    package_name = read_json(reports_dir / "closure-report.json")["packages"][0]
    extension_id = read_json(reports_dir / "extensions-index.json")["extensions"][0]["id"]

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        layer = run_json(tool, ["explain", "layer", "0", "--report", str(reports_dir)])
        if not layer.get("group") or len(layer.get("members") or []) < 1:
            fail("explain layer did not return expected layer data")

        if run_json(tool, ["explain", "package", package_name, "--report", str(reports_dir)]) != package_name:
            fail("explain package returned the wrong package")

        extension = run_json(tool, ["explain", "extension", extension_id, "--report", str(reports_dir)])
        if extension.get("id") != extension_id:
            fail("explain extension returned the wrong extension")
        if not str(extension.get("source", "")).startswith("nix-vscode-extensions."):
            fail("extension source metadata is incomplete")
        source_lock = extension.get("sourceLock") or {}
        if not all(source_lock.get(key) for key in ["ref", "sha256", "archiveName"]):
            fail("extension source lock metadata is incomplete")
        artifacts = extension.get("artifacts") or {}
        projection_artifact = artifacts.get("projection") or {}
        archive_artifact = artifacts.get("archive") or {}
        if projection_artifact.get("enabled") is not True or not projection_artifact.get("path"):
            fail("extension projection artifact metadata is incomplete")
        if archive_artifact.get("enabled") is not False:
            fail("extension archive artifact should be disabled by default")
        if not (extension.get("validation") or {}).get("strategy"):
            fail("extension validation strategy missing")

        env_path = run_json(tool, ["explain", "env", "PATH", "--report", str(reports_dir)])
        if env_path.get("sources", [None])[0] != "compiler.env.path" or not env_path.get("pathEntries"):
            fail("explain env PATH returned unexpected data")

        filesystem = run_json(tool, ["explain", "filesystem", "--report", str(reports_dir)])
        if (filesystem.get("user") or {}).get("name") != "vscode" or (filesystem.get("user") or {}).get("uid") != 1000:
            fail("filesystem report user mismatch")
        if not filesystem.get("directories"):
            fail("filesystem report missing directories")

        image_plan = run_json(tool, ["explain", "image-plan", "--report", str(reports_dir)])
        if image_plan.get("image") != image_name:
            fail("image-plan report image mismatch")

        security = run_json(tool, ["explain", "security", "--report", str(reports_dir)])
        if security != read_json(reports_dir / "security-report.json"):
            fail("explain security must match security-report.json")

        metadata_preview = read_json(reports_dir / "metadata-merged-preview.json")
        if "dockerAccess" in metadata_preview:
            fail("metadata preview contains forbidden Docker metadata")
        protected_mounts = metadata_preview.get("mounts")
        if (
            not isinstance(protected_mounts, list)
            or len(protected_mounts) != 1
            or not isinstance(protected_mounts[0], str)
        ):
            fail("metadata preview must contain exactly one protected mount")
        protected_mount = protected_mounts[0]
        writable_protected_mount = protected_mount.replace(",readonly", "")
        if writable_protected_mount == protected_mount:
            fail("metadata preview protected mount must be readonly")

        run_tool(tool, ["check", str(reports_dir / "metadata-label.json")])
        project_devcontainer = tmpdir / "project-devcontainer.json"
        write_json(
            project_devcontainer,
            {"name": "fixture", "updateRemoteUserUID": False},
        )
        run_tool(tool, ["check", str(project_devcontainer)])

        project_with_protected_mount = tmpdir / "project-protected-mount-devcontainer.json"
        write_json(
            project_with_protected_mount,
            {
                "name": "fixture",
                "mounts": [protected_mount],
            },
        )
        run_tool(tool, ["check", str(project_with_protected_mount)])

        bad_label = tmpdir / "bad-label.json"
        write_json(bad_label, [{"remoteUser": "vscode"}])
        bad_label_result = run_tool(tool, ["check", str(bad_label)], check=False)
        if bad_label_result.returncode == 0 or "must protect .devcontainer" not in bad_label_result.stderr:
            fail("expected check to reject image metadata without protected mount")

        bad_label_run_args = tmpdir / "bad-label-run-args.json"
        write_json(
            bad_label_run_args,
            [
                {
                    "remoteUser": "vscode",
                    "containerUser": "vscode",
                    "updateRemoteUserUID": False,
                    "mounts": [protected_mount],
                    "runArgs": ["-u1000:100"],
                }
            ],
        )
        bad_label_run_args_result = run_tool(tool, ["check", str(bad_label_run_args)], check=False)
        if bad_label_run_args_result.returncode == 0 or "only support the vscode user" not in bad_label_run_args_result.stderr:
            fail("expected check to reject image metadata runArgs user override")

        bad_mount = tmpdir / "bad-mount-devcontainer.json"
        write_json(
            bad_mount,
            {
                "name": "fixture",
                "mounts": [writable_protected_mount],
            },
        )
        bad_mount_result = run_tool(tool, ["check", str(bad_mount)], check=False)
        if bad_mount_result.returncode == 0 or "must not override the protected .devcontainer mount" not in bad_mount_result.stderr:
            fail("expected check to reject writable protected mount override")

        bad_user = tmpdir / "bad-user-devcontainer.json"
        write_json(bad_user, {"name": "fixture", "remoteUser": "vscode"})
        bad_user_result = run_tool(tool, ["check", str(bad_user)], check=False)
        if bad_user_result.returncode == 0 or "only support the vscode user" not in bad_user_result.stderr:
            fail("expected check to reject remoteUser override")

        bad_container_user = tmpdir / "bad-container-user-devcontainer.json"
        write_json(bad_container_user, {"name": "fixture", "containerUser": "vscode"})
        bad_container_user_result = run_tool(tool, ["check", str(bad_container_user)], check=False)
        if bad_container_user_result.returncode == 0 or "only support the vscode user" not in bad_container_user_result.stderr:
            fail("expected check to reject containerUser override")

        bad_uid = tmpdir / "bad-uid-devcontainer.json"
        write_json(bad_uid, {"name": "fixture", "updateRemoteUserUID": True})
        bad_uid_result = run_tool(tool, ["check", str(bad_uid)], check=False)
        if bad_uid_result.returncode == 0 or "only support the vscode user" not in bad_uid_result.stderr:
            fail("expected check to reject updateRemoteUserUID")

        bad_run_args = tmpdir / "bad-run-args-devcontainer.json"
        write_json(bad_run_args, {"name": "fixture", "runArgs": ["--user", "1000:100"]})
        bad_run_args_result = run_tool(tool, ["check", str(bad_run_args)], check=False)
        if bad_run_args_result.returncode == 0 or "only support the vscode user" not in bad_run_args_result.stderr:
            fail("expected check to reject runArgs --user")

        bad_run_args_equals = tmpdir / "bad-run-args-equals-devcontainer.json"
        write_json(bad_run_args_equals, {"name": "fixture", "runArgs": ["--user=1000:100"]})
        bad_run_args_equals_result = run_tool(tool, ["check", str(bad_run_args_equals)], check=False)
        if bad_run_args_equals_result.returncode == 0 or "only support the vscode user" not in bad_run_args_equals_result.stderr:
            fail("expected check to reject runArgs --user=<uid>:<gid>")

        bad_run_args_short = tmpdir / "bad-run-args-short-devcontainer.json"
        write_json(bad_run_args_short, {"name": "fixture", "runArgs": ["-u1000:100"]})
        bad_run_args_short_result = run_tool(tool, ["check", str(bad_run_args_short)], check=False)
        if bad_run_args_short_result.returncode == 0 or "only support the vscode user" not in bad_run_args_short_result.stderr:
            fail("expected check to reject runArgs -u<uid>:<gid>")

        diff_same = run_json(
            tool,
            ["diff", str(reports_dir / "layer-plan.json"), str(reports_dir / "layer-plan.json")],
        )
        if diff_same != {"added": [], "removed": [], "changed": []}:
            fail(f"same layer plan diff changed unexpectedly: {diff_same}")

        modified_layer_plan = read_json(reports_dir / "layer-plan.json")
        modified_layer_plan["layers"][0]["priority"] += 1
        modified_path = tmpdir / "layer-plan-modified.json"
        write_json(modified_path, modified_layer_plan)
        diff_changed = run_json(tool, ["diff", str(reports_dir / "layer-plan.json"), str(modified_path)])
        if len(diff_changed.get("changed") or []) != 1:
            fail("expected exactly one changed layer")
        if "priority changed" not in diff_changed["changed"][0].get("reasons", []):
            fail("expected priority changed diff reason")

        missing_package = run_tool(
            tool,
            ["explain", "package", "does-not-exist", "--report", str(reports_dir)],
            check=False,
        )
        if missing_package.returncode == 0 or "package not found: does-not-exist" not in missing_package.stderr:
            fail("expected missing package failure")

        missing_env = run_tool(
            tool,
            ["explain", "env", "DOES_NOT_EXIST", "--report", str(reports_dir)],
            check=False,
        )
        if missing_env.returncode == 0 or "environment entry not found: DOES_NOT_EXIST" not in missing_env.stderr:
            fail("expected missing env failure")

        no_path_env = os.environ.copy()
        no_path_env["PATH"] = ""
        doctor = run_tool(
            tool,
            ["doctor", "image", f"ghcr.io/example/devcontainer-{image_name}:latest"],
            env=no_path_env,
        )
        if "docker unavailable in current environment" not in doctor.stdout:
            fail("expected doctor to report unavailable docker")

    print(f"report-cli-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
