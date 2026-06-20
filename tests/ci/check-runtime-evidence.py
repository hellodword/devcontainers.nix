#!/usr/bin/env python3
import csv
import json
import pathlib
import sys


REQUIRED_REPORT_FILES = {
    "ci-plan.json",
    "closure-report.json",
    "env-report.json",
    "extensions-index.json",
    "extensions-report.json",
    "filesystem-report.json",
    "fhs-runtime-report.json",
    "graph.json",
    "graph-normalized.json",
    "graph-duplicates-report.json",
    "image-plan.json",
    "layer-plan.json",
    "libraries-report.json",
    "metadata-label.json",
    "metadata-merged-preview.json",
    "metadata-schema-report.json",
    "security-report.json",
    "smoke-test-plan.json",
    "tasks.json",
}


def fail(message: str) -> None:
    print(f"runtime-evidence-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_text(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def read_json(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def require_file(path: pathlib.Path) -> None:
    if not path.is_file():
        fail(f"missing file: {path}")


def require_dir(path: pathlib.Path) -> None:
    if not path.is_dir():
        fail(f"missing directory: {path}")


def load_summary(path: pathlib.Path) -> dict[tuple[str, str], int]:
    require_file(path)
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows = list(reader)
    if reader.fieldnames != ["mode", "name", "exit_code"]:
        fail("summary.tsv must have header: mode<TAB>name<TAB>exit_code")
    summary: dict[tuple[str, str], int] = {}
    for row in rows:
        key = (row["mode"], row["name"])
        summary[key] = int(row["exit_code"])
    return summary


def validate_reports(section_dir: pathlib.Path) -> None:
    reports_dir = section_dir / "reports"
    require_dir(reports_dir)
    missing = sorted(report for report in REQUIRED_REPORT_FILES if not (reports_dir / report).is_file())
    if missing:
        fail(f"{section_dir.name} reports missing files: {', '.join(missing)}")


def validate_run_artifact(
    evidence_dir: pathlib.Path,
    summary: dict[tuple[str, str], int],
    section: str,
    run_name: str,
) -> tuple[str, str]:
    run_dir = evidence_dir / section / run_name
    require_dir(run_dir)
    command_path = run_dir / "command.txt"
    stdout_path = run_dir / "stdout.txt"
    stderr_path = run_dir / "stderr.txt"
    exit_code_path = run_dir / "exit-code.txt"
    for path in [command_path, stdout_path, stderr_path, exit_code_path]:
        require_file(path)

    command_text = read_text(command_path).strip()
    stdout_text = read_text(stdout_path)
    stderr_text = read_text(stderr_path)
    exit_code = int(read_text(exit_code_path).strip())
    summary_exit = summary.get((section, run_name))
    if summary_exit is None:
        fail(f"summary.tsv missing row for {section}/{run_name}")
    if summary_exit != exit_code:
        fail(f"summary.tsv exit code mismatch for {section}/{run_name}: {summary_exit} != {exit_code}")
    if exit_code != 0:
        fail(f"{section}/{run_name} must exit 0, got {exit_code}")
    if not command_text:
        fail(f"{section}/{run_name} command.txt must not be empty")
    return stdout_text, stderr_text


def validate_oci_section(evidence_dir: pathlib.Path, summary: dict[tuple[str, str], int], section: str) -> None:
    section_dir = evidence_dir / section
    require_dir(section_dir)
    for path_name in ["image-ref.txt", "image-path.txt", "smoke-plan-path.txt"]:
        require_file(section_dir / path_name)
    validate_reports(section_dir)

    for run_name in [
        "image-load",
        "docker-inspect",
        "docker-run-env",
        "docker-run-bash",
        "docker-run-user",
        "docker-run-task-runner",
        "docker-run-required-tools",
    ]:
        validate_run_artifact(evidence_dir, summary, section, run_name)

    inspect_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-inspect")
    inspect_json = json.loads(inspect_stdout)
    if not isinstance(inspect_json, list) or not inspect_json:
        fail(f"{section}/docker-inspect stdout must be a non-empty JSON array")
    image_config = inspect_json[0].get("Config") or {}
    if image_config.get("User") != "vscode":
        fail(f"{section}/docker-inspect must report vscode user")
    if image_config.get("WorkingDir") != "/workspaces":
        fail(f"{section}/docker-inspect must report /workspaces working directory")
    if image_config.get("Entrypoint") != ["/usr/local/bin/devcontainer-entrypoint"]:
        fail(f"{section}/docker-inspect must report the expected entrypoint")
    if image_config.get("Cmd") != ["sleep", "infinity"]:
        fail(f"{section}/docker-inspect must report the expected default command")
    labels = image_config.get("Labels") or {}
    metadata_label_raw = labels.get("devcontainer.metadata")
    if not metadata_label_raw:
        fail(f"{section}/docker-inspect must include devcontainer.metadata label")
    metadata_label = json.loads(metadata_label_raw)
    report_metadata_label = read_json(section_dir / "reports" / "metadata-label.json")
    if metadata_label != report_metadata_label:
        fail(f"{section}/docker-inspect devcontainer.metadata label must match reports/metadata-label.json")

    env_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-env")
    if "PATH=" not in env_stdout or "HOME=/home/vscode" not in env_stdout:
        fail(f"{section}/docker-run-env must include PATH and HOME")

    bash_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-bash")
    if bash_stdout.strip() != "ok":
        fail(f"{section}/docker-run-bash must print ok")

    user_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-user")
    if "uid=1000(vscode)" not in user_stdout:
        fail(f"{section}/docker-run-user must show uid=1000(vscode)")

    task_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-task-runner")
    if not task_stdout.strip():
        fail(f"{section}/docker-run-task-runner must produce non-empty stdout")

    tools_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-required-tools")
    for tool in ["docker", "codex", "nix-locate"]:
        if tool not in tools_stdout:
            fail(f"{section}/docker-run-required-tools must include {tool}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: tests/ci/check-runtime-evidence.py <evidence-dir>", file=sys.stderr)
        return 1

    evidence_dir = pathlib.Path(sys.argv[1])
    require_dir(evidence_dir)
    summary = load_summary(evidence_dir / "summary.tsv")

    mode = read_text(evidence_dir / "mode.txt").strip()
    require_file(evidence_dir / "generated-at.txt")
    require_file(evidence_dir / "invocation.txt")

    oci_sections = sorted(path.name for path in evidence_dir.iterdir() if path.is_dir() and path.name.startswith("oci-"))
    if mode == "oci":
        if len(oci_sections) != 1:
            fail("oci mode evidence must contain exactly one oci-* section")
    elif mode == "full":
        if not oci_sections:
            fail("full mode evidence must contain oci-* sections")
    else:
        fail(f"unsupported mode in mode.txt: {mode}")

    for section in oci_sections:
        validate_oci_section(evidence_dir, summary, section)

    print(f"runtime-evidence-check ok: {evidence_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
