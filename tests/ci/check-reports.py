#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
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
    "image-plan.json",
    "layer-plan.json",
    "metadata-label.json",
    "metadata-merged-preview.json",
    "metadata-schema-report.json",
    "security-report.json",
    "smoke-test-plan.json",
}

REQUIRED_CI_REPORT_FILES = REQUIRED_REPORT_FILES - {"ci-plan.json"}


def read_json(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def fail(message: str):
    print(f"report-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tests/ci/check-reports.py <reports-dir> <image-name>", file=sys.stderr)
        return 1

    reports_dir = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    missing_reports = sorted(
        report_name for report_name in REQUIRED_REPORT_FILES if not (reports_dir / report_name).is_file()
    )
    if missing_reports:
        fail(f"reports directory missing files: {', '.join(missing_reports)}")

    metadata_label = read_json(reports_dir / "metadata-label.json")
    metadata_schema = read_json(reports_dir / "metadata-schema-report.json")
    layer_plan = read_json(reports_dir / "layer-plan.json")
    extensions_report = read_json(reports_dir / "extensions-report.json")
    docker_access_report = read_json(reports_dir / "docker-access-report.json")
    smoke_plan = read_json(reports_dir / "smoke-test-plan.json")
    image_plan = read_json(reports_dir / "image-plan.json")
    security_report = read_json(reports_dir / "security-report.json")
    fhs_runtime_report = read_json(reports_dir / "fhs-runtime-report.json")
    ci_plan = read_json(reports_dir / "ci-plan.json")

    if not isinstance(metadata_label, list):
        fail("metadata-label.json must be a JSON array")

    if not metadata_schema["hasRemoteUser"]:
        fail("metadata schema must include remoteUser")
    if not metadata_schema["hasLifecycle"]:
        fail("metadata schema must include lifecycle commands")
    if not metadata_schema["hasVscodeCustomizations"]:
        fail("metadata schema must include VS Code customizations")

    layer_count = len(layer_plan["layers"])
    layer_max = int(layer_plan["budget"]["max"])
    if layer_count > layer_max:
        fail(f"layer count {layer_count} exceeds budget {layer_max}")

    if not smoke_plan["tests"]:
        fail("smoke-test-plan.json must include at least one test")

    smoke_plan_file = reports_dir / "smoke-test-plan.json"
    smoke_checker = pathlib.Path(
        os.environ.get("CHECK_SMOKE_PLAN", pathlib.Path(__file__).with_name("check-smoke-plan.py"))
    )
    subprocess.run(
        ["python3", str(smoke_checker), str(smoke_plan_file), image_name],
        check=True,
    )

    if image_plan["entrypoint"] != ["/usr/local/bin/devcontainer-entrypoint"]:
        fail("image-plan.json entrypoint mismatch")

    if not fhs_runtime_report["enabled"]:
        fail("fhs-runtime-report.json must confirm FHS runtime is enabled")

    if not extensions_report["validation"]["noNetworkDuringProjection"]:
        fail("extensions projection must stay offline")

    ci_report_files = set(ci_plan["reportFiles"])
    missing_ci_reports = sorted(REQUIRED_CI_REPORT_FILES - ci_report_files)
    if missing_ci_reports:
        fail(f"ci-plan.json missing report files: {', '.join(missing_ci_reports)}")

    if image_name == "nix-dind":
        if not docker_access_report["enabled"]:
            fail("nix-dind must enable docker access")
        if docker_access_report["privilegeReport"]["level"] != "high":
            fail("nix-dind docker access must declare high privilege")
    else:
        if docker_access_report["enabled"]:
            fail(f"{image_name} must not enable docker access")
        if docker_access_report["privilegeReport"]["level"] != "none":
            fail(f"{image_name} docker access privilege report must be none")

    if not security_report["dockerAccessOnlyInNixDind"]:
        fail("security-report.json must confirm docker access isolation")
    if not security_report["lifecycleLogRedaction"]:
        fail("security-report.json must confirm lifecycle log redaction")
    if not security_report["extensionProjectionLogRedaction"]:
        fail("security-report.json must confirm extension projection log redaction")
    if not security_report["remoteTcpRequiresTls"]:
        fail("security-report.json must confirm remote TCP TLS policy")
    if not security_report["shellInitHasNoSideEffects"]:
        fail("security-report.json must confirm shell init remains side-effect free")

    print(f"report-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
