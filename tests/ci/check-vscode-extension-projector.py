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


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def main() -> int:
    projector_root = os.environ.get("DEVCONTAINER_PROJECTOR")
    if not projector_root:
        fail("DEVCONTAINER_PROJECTOR is required")
    projector = Path(projector_root) / "bin" / "vscode-extension-projector"

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        source_ext_link = tmpdir / "source-ext-link"
        source_ext_copy = tmpdir / "source-ext-copy"
        symlink_target = tmpdir / "TOKEN=super-secret" / "target-symlink" / "extensions"
        copy_target = tmpdir / "SECRET=another-secret" / "target-copy" / "extensions"
        source_ext_link.mkdir()
        source_ext_copy.mkdir()
        symlink_target.mkdir(parents=True)
        copy_target.mkdir(parents=True)
        (source_ext_link / "package.json").write_text(
            json.dumps({"name": "example.extension", "publisher": "example", "version": "0.0.0"}),
            encoding="utf-8",
        )
        (source_ext_copy / "package.json").write_text(
            json.dumps({"name": "example.native", "publisher": "example", "version": "0.0.0"}),
            encoding="utf-8",
        )

        index_file = tmpdir / "index.json"
        write_json(
            index_file,
            {
                "projectionTargets": [str(symlink_target), str(copy_target)],
                "extensions": [
                    {
                        "id": "example.extension",
                        "path": str(source_ext_link),
                        "projection": "symlink",
                        "required": True,
                    },
                    {
                        "id": "example.native",
                        "path": str(source_ext_copy),
                        "projection": "copy-if-needed",
                        "required": True,
                    },
                    {
                        "id": "example.optional-missing",
                        "path": str(
                            tmpdir / "github_pat_optionalmissing000000000000000000000000" / "missing"
                        ),
                        "projection": "symlink",
                        "required": False,
                    },
                ],
            },
        )
        result = run([str(projector), "activate", "--index", str(index_file)])
        combined_log = result.stdout + result.stderr
        if not (symlink_target / source_ext_link.name).is_symlink():
            fail("symlink projection missing")
        if not (copy_target / source_ext_copy.name).is_dir():
            fail("copy projection missing")
        if "[REDACTED]" not in combined_log:
            fail(f"expected redacted projector log:\n{combined_log}")
        for secret in [
            "super-secret",
            "another-secret",
            "github_pat_optionalmissing000000000000000000000000",
        ]:
            if secret in combined_log:
                fail(f"projector log leaked {secret}")

        missing_required_index = tmpdir / "missing-required-index.json"
        write_json(
            missing_required_index,
            {
                "projectionTargets": [str(symlink_target)],
                "extensions": [
                    {
                        "id": "example.required-missing",
                        "path": str(tmpdir / "KEY=required-missing-secret" / "missing"),
                        "projection": "symlink",
                        "required": True,
                    },
                ],
            },
        )
        missing_required = run(
            [str(projector), "activate", "--index", str(missing_required_index)],
            check=False,
        )
        if missing_required.returncode == 0:
            fail("expected required missing extension source to fail")
        missing_required_log = missing_required.stdout + missing_required.stderr
        if "[REDACTED]" not in missing_required_log or "required-missing-secret" in missing_required_log:
            fail(f"required missing source log redaction failed:\n{missing_required_log}")

        outside_marker = tmpdir / "outside-marker"
        outside_marker.write_text("keep", encoding="utf-8")
        unsafe_index = tmpdir / "unsafe-index.json"
        write_json(
            unsafe_index,
            {
                "projectionTargets": [str(tmpdir / "safe-target")],
                "extensions": [
                    {
                        "id": "example.escape",
                        "path": str(source_ext_link / ".."),
                        "projection": "copy-if-needed",
                        "required": True,
                    }
                ],
            },
        )
        unsafe = run([str(projector), "activate", "--index", str(unsafe_index)], check=False)
        if unsafe.returncode == 0 or "unsafe extension destination name" not in unsafe.stderr:
            fail(f"expected unsafe destination failure, got stderr:\n{unsafe.stderr}")
        if outside_marker.read_text(encoding="utf-8") != "keep":
            fail("unsafe projection removed a file outside the target")

    print("vscode-extension-projector-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
