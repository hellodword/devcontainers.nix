#!/usr/bin/env python3
import json
import pathlib
import re
import sys

from lib.json_checks import fail as fail_with_prefix
from lib.json_checks import parse_env_entries, read_json, walk_strings
from layer_budget import BudgetError, check_layer_budget


PREFIX = "image-artifact-check"
SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)


def fail(message: str) -> None:
    fail_with_prefix(PREFIX, message)


def main() -> int:
    if len(sys.argv) not in {4, 5}:
        print(
            "usage: tests/ci/check-image-tar.py <nix2container-image-json> <reports-dir> <image-name> [expected-devpkg-nixpkgs-ref]",
            file=sys.stderr,
        )
        return 1

    image_path = pathlib.Path(sys.argv[1])
    reports_dir = pathlib.Path(sys.argv[2])
    image_name = sys.argv[3]
    expected_devpkg_nixpkgs_ref = sys.argv[4] if len(sys.argv) == 5 else None

    if not image_path.is_file():
        fail(f"image artifact is not a file: {image_path}")
    if image_path.stat().st_size == 0:
        fail("image artifact is empty")

    image_json = read_json(image_path, PREFIX)
    image_plan = read_json(reports_dir / "image-plan.json", PREFIX)
    ci_plan = read_json(reports_dir / "ci-plan.json", PREFIX)
    env_report = read_json(reports_dir / "env-report.json", PREFIX)
    expected_metadata_label = read_json(reports_dir / "metadata-label.json", PREFIX)
    layer_plan = read_json(reports_dir / "layer-plan.json", PREFIX)
    layer_closure_report = read_json(reports_dir / "layer-closure-report.json", PREFIX)
    try:
        check_layer_budget(image_json, layer_plan, layer_closure_report)
    except BudgetError as exc:
        fail(str(exc))

    if image_plan.get("image") != image_name:
        fail("image-plan.json image must match the checked image")
    if ci_plan.get("image") != image_name:
        fail("ci-plan.json image must match the checked image")

    if image_json.get("version") != 1:
        fail("image artifact must use nix2container JSON version 1")
    expected_architectures = ci_plan.get("architectures") or []
    if "linux/amd64" in expected_architectures and image_json.get("arch") != "amd64":
        fail("image artifact arch must match ci-plan.json")

    image_config = image_json.get("image-config")
    if not isinstance(image_config, dict):
        fail("image artifact must contain an image-config object")
    if image_config.get("User") != image_plan.get("user"):
        fail("image artifact User must match image-plan.json")
    if image_config.get("WorkingDir") != image_plan.get("workingDir"):
        fail("image artifact WorkingDir must match image-plan.json")
    if image_config.get("Entrypoint") != image_plan.get("entrypoint"):
        fail("image artifact Entrypoint must match image-plan.json")

    actual_env = parse_env_entries(image_config.get("Env"), PREFIX)
    expected_env = env_report.get("containerEnv")
    if not isinstance(expected_env, dict) or not all(
        isinstance(name, str) and isinstance(value, str) for name, value in expected_env.items()
    ):
        fail("env-report.json containerEnv must be a string map")
    if actual_env != expected_env:
        missing = sorted(set(expected_env) - set(actual_env))
        extra = sorted(set(actual_env) - set(expected_env))
        changed = sorted(name for name in set(expected_env) & set(actual_env) if expected_env[name] != actual_env[name])
        fail(f"image artifact Env must match env-report.json; missing={missing}, extra={extra}, changed={changed}")

    if expected_devpkg_nixpkgs_ref is not None:
        if not re.fullmatch(r"path:/nix/store/[a-z0-9]{32}-source", expected_devpkg_nixpkgs_ref):
            fail("expected DEVPKG_NIXPKGS_REF must be a locked nixpkgs store source")
        if actual_env.get("DEVPKG_NIXPKGS_REF") != expected_devpkg_nixpkgs_ref:
            fail("image artifact DEVPKG_NIXPKGS_REF must match expected locked nixpkgs source")

    labels = image_config.get("Labels")
    if not isinstance(labels, dict) or "devcontainer.metadata" not in labels:
        fail("image artifact must include devcontainer metadata")
    try:
        actual_metadata_label = json.loads(labels["devcontainer.metadata"])
    except json.JSONDecodeError as exc:
        fail(f"devcontainer.metadata label must be valid JSON: {exc}")
    if actual_metadata_label != expected_metadata_label:
        fail("image artifact devcontainer.metadata label must match metadata-label.json")

    for text in walk_strings(image_json):
        if SENSITIVE_VALUE_RE.search(text):
            fail("image artifact appears to contain sensitive material")

    print(f"image-artifact-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
