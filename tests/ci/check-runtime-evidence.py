#!/usr/bin/env python3
import argparse
import csv
import json
import pathlib
import sys


REQUIRED_REPORT_FILES = {
    "ci-plan.json",
    "closure-report.json",
    "docker-access-report.json",
    "env-report.json",
    "extensions-index.json",
    "extensions-report.json",
    "fhs-runtime-report.json",
    "graph.json",
    "graph-normalized.json",
    "graph-duplicates-report.json",
    "image-plan.json",
    "layer-plan.json",
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
        try:
            summary[key] = int(row["exit_code"])
        except ValueError as exc:
            raise SystemExit(f"invalid exit code in summary.tsv for {key}: {row['exit_code']}") from exc
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
    *,
    expect_success: bool = True,
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
    if expect_success and exit_code != 0:
        fail(f"{section}/{run_name} must exit 0, got {exit_code}")
    if not command_text:
        fail(f"{section}/{run_name} command.txt must not be empty")
    return stdout_text, stderr_text


def validate_oci_section(evidence_dir: pathlib.Path, summary: dict[tuple[str, str], int], section: str) -> None:
    section_dir = evidence_dir / section
    require_dir(section_dir)
    for path_name in ["image-ref.txt", "oci-path.txt", "smoke-plan-path.txt"]:
        require_file(section_dir / path_name)
    validate_reports(section_dir)

    for run_name in [
        "docker-load",
        "docker-inspect",
        "docker-run-env",
        "docker-run-bash",
        "docker-run-task-runner",
    ]:
        validate_run_artifact(evidence_dir, summary, section, run_name)

    inspect_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-inspect")
    inspect_json = json.loads(inspect_stdout)
    if not isinstance(inspect_json, list) or not inspect_json:
        fail(f"{section}/docker-inspect stdout must be a non-empty JSON array")
    image_config = inspect_json[0].get("Config") or {}
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

    inspect_env = image_config.get("Env") or []
    if not isinstance(inspect_env, list):
        fail(f"{section}/docker-inspect Config.Env must be a list")
    report_merged = read_json(section_dir / "reports" / "metadata-merged-preview.json")
    report_container_env = report_merged.get("containerEnv") or {}
    for key, value in report_container_env.items():
        expected_entry = f"{key}={value}"
        if expected_entry not in inspect_env:
            fail(f"{section}/docker-inspect Config.Env missing {expected_entry}")

    env_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-env")
    if "PATH=" not in env_stdout:
        fail(f"{section}/docker-run-env must include PATH in stdout")

    bash_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-bash")
    if bash_stdout.strip() != "ok":
        fail(f"{section}/docker-run-bash must print ok")

    task_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-run-task-runner")
    if not task_stdout.strip():
        fail(f"{section}/docker-run-task-runner must produce non-empty stdout")
    expected_tasks = read_json(section_dir / "reports" / "tasks.json").get("tasks") or []
    for task in expected_tasks:
        expected_line = f"{task['name']}\t{task['phase']}\tonce={str(task['once']).lower()}"
        if expected_line not in task_stdout:
            fail(f"{section}/docker-run-task-runner missing task line: {expected_line}")


def validate_docker_access_section(
    evidence_dir: pathlib.Path,
    summary: dict[tuple[str, str], int],
    *,
    allow_remote_tcp_skip: bool,
) -> None:
    section = "docker-access"
    section_dir = evidence_dir / section
    require_dir(section_dir)
    for path_name in ["image-ref.txt", "oci-path.txt", "host-docker-socket.txt"]:
        require_file(section_dir / path_name)
    validate_reports(section_dir)

    for run_name in [
        "docker-load",
        "docker-version",
        "docker-info",
        "docker-buildx-version",
        "docker-compose-version",
        "docker-task-runner",
        "docker-process-list",
        "docker-build-run-smoke",
    ]:
        validate_run_artifact(evidence_dir, summary, section, run_name)

    version_stdout, version_stderr = validate_run_artifact(evidence_dir, summary, section, "docker-version")
    if not (version_stdout.strip() or version_stderr.strip()):
        fail("docker-access/docker-version must emit output")

    task_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-task-runner")
    if not task_stdout.strip():
        fail("docker-access/docker-task-runner must produce non-empty stdout")
    process_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-process-list")
    if "dockerd" in process_stdout:
        fail("docker-access/docker-process-list must not show a running dockerd process")

    smoke_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "docker-build-run-smoke")
    if "ok" not in smoke_stdout:
        fail("docker-access/docker-build-run-smoke must include ok in stdout")

    for run_name in [
        "docker-version",
        "docker-info",
        "docker-buildx-version",
        "docker-compose-version",
        "docker-task-runner",
        "docker-process-list",
        "docker-build-run-smoke",
    ]:
        command_text = read_text(evidence_dir / section / run_name / "command.txt")
        if "--privileged" in command_text:
            fail(f"docker-access/{run_name} must not require --privileged")

    remote_skip = section_dir / "remote-tcp-skipped.txt"
    remote_host = section_dir / "remote-docker-host.txt"
    remote_certs = section_dir / "remote-docker-certs-dir.txt"
    has_remote_evidence = remote_host.is_file()

    if has_remote_evidence:
        remote_host_value = read_text(remote_host).strip()
        if not remote_host_value.startswith("tcp://"):
            fail("docker-access remote-docker-host.txt must start with tcp://")
        explain_stdout, _ = validate_run_artifact(evidence_dir, summary, section, "remote-tcp-explain")
        if f"mode={remote_host_value}" not in explain_stdout:
            fail("docker-access/remote-tcp-explain must report the configured DOCKER_HOST")
        if remote_certs.is_file():
            if "tls_verify=1" not in explain_stdout:
                fail("docker-access/remote-tcp-explain must confirm DOCKER_TLS_VERIFY=1 when certs are provided")
            if "cert_path=/run/docker-certs" not in explain_stdout:
                fail("docker-access/remote-tcp-explain must confirm /run/docker-certs when certs are provided")
        elif "tls_verify=0" not in explain_stdout:
            fail("docker-access/remote-tcp-explain must confirm TLS is disabled when certs are not provided")
        validate_run_artifact(evidence_dir, summary, section, "remote-tcp-docker-version")
    else:
        if remote_skip.is_file() and allow_remote_tcp_skip:
            return
        if remote_skip.is_file():
            fail(
                "docker-access remote TCP evidence was skipped; rerun without skip or pass --allow-remote-tcp-skip"
            )
        fail("docker-access must include remote TCP evidence or an explicit skip marker")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence_dir")
    parser.add_argument("--allow-remote-tcp-skip", action="store_true")
    args = parser.parse_args()

    evidence_dir = pathlib.Path(args.evidence_dir)
    require_dir(evidence_dir)
    summary = load_summary(evidence_dir / "summary.tsv")

    mode = read_text(evidence_dir / "mode.txt").strip()
    require_file(evidence_dir / "generated-at.txt")
    require_file(evidence_dir / "invocation.txt")

    if mode == "oci":
        oci_sections = sorted(path.name for path in evidence_dir.iterdir() if path.is_dir() and path.name.startswith("oci-"))
        if len(oci_sections) != 1:
            fail("oci mode evidence must contain exactly one oci-* section")
        validate_oci_section(evidence_dir, summary, oci_sections[0])
    elif mode == "docker-access":
        validate_docker_access_section(evidence_dir, summary, allow_remote_tcp_skip=args.allow_remote_tcp_skip)
    elif mode == "full":
        for section in ["oci-nix", "oci-nix-dind"]:
            validate_oci_section(evidence_dir, summary, section)
        validate_docker_access_section(evidence_dir, summary, allow_remote_tcp_skip=args.allow_remote_tcp_skip)
    else:
        fail(f"unsupported mode in mode.txt: {mode}")

    print(f"runtime-evidence-check ok: {evidence_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
