#!/usr/bin/env python3
import json
import pathlib
import subprocess
import sys


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

    metadata_label = read_json(reports_dir / "metadata-label.json")
    layer_plan = read_json(reports_dir / "layer-plan.json")
    extensions_report = read_json(reports_dir / "extensions-report.json")
    docker_access_report = read_json(reports_dir / "docker-access-report.json")
    smoke_plan = read_json(reports_dir / "smoke-test-plan.json")
    image_plan = read_json(reports_dir / "image-plan.json")
    security_report = read_json(reports_dir / "security-report.json")

    if not isinstance(metadata_label, list):
        fail("metadata-label.json must be a JSON array")

    layer_count = len(layer_plan["layers"])
    layer_max = int(layer_plan["budget"]["max"])
    if layer_count > layer_max:
        fail(f"layer count {layer_count} exceeds budget {layer_max}")

    if not smoke_plan["tests"]:
        fail("smoke-test-plan.json must include at least one test")

    smoke_plan_file = reports_dir / "smoke-test-plan.json"
    subprocess.run(
        ["python3", "tests/ci/check-smoke-plan.py", str(smoke_plan_file), image_name],
        check=True,
    )

    if image_plan["entrypoint"] != ["/usr/local/bin/devcontainer-entrypoint"]:
        fail("image-plan.json entrypoint mismatch")

    if not extensions_report["validation"]["noNetworkDuringProjection"]:
        fail("extensions projection must stay offline")

    if image_name == "nix-dind":
        if not docker_access_report["enabled"]:
            fail("nix-dind must enable docker access")
    else:
        if docker_access_report["enabled"]:
            fail(f"{image_name} must not enable docker access")

    if not security_report["dockerAccessOnlyInNixDind"]:
        fail("security-report.json must confirm docker access isolation")

    print(f"report-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
