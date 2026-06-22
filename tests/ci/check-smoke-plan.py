#!/usr/bin/env python3
import json
import pathlib
import sys


def fail(message: str):
    print(f"smoke-plan-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    if len(sys.argv) not in {3, 4}:
        print(
            "usage: tests/ci/check-smoke-plan.py <smoke-plan.json> <profile-report.json> [image-name]",
            file=sys.stderr,
        )
        return 1

    plan_path = pathlib.Path(sys.argv[1])
    profile_report_path = pathlib.Path(sys.argv[2])
    image_name = sys.argv[3] if len(sys.argv) == 4 else None

    plan = read_json(plan_path)
    profile_report = read_json(profile_report_path)

    tests = plan.get("tests") or []
    ids = [test.get("id") for test in tests]
    if len(ids) != len(set(ids)):
        fail("smoke-test-plan.json must not contain duplicate test ids")
    for test in tests:
        test_id = test.get("id")
        if not isinstance(test_id, str) or not test_id:
            fail("each smoke test must include a non-empty id")
        if not isinstance(test.get("tags"), list) or not all(isinstance(tag, str) and tag for tag in test["tags"]):
            fail(f"{test_id} must include string tags")
        if not isinstance(test.get("command"), list) or not all(
            isinstance(part, str) and part for part in test["command"]
        ):
            fail(f"{test_id} must include a non-empty command array")
        if not isinstance(test.get("requires"), list) or not all(
            isinstance(requirement, str) and requirement for requirement in test["requires"]
        ):
            fail(f"{test_id} must include a requires array")
        if not isinstance(test.get("timeoutSeconds"), int) or test["timeoutSeconds"] < 1:
            fail(f"{test_id} must include a positive timeoutSeconds value")

    required = {
        capability
        for capability in (profile_report.get("tests") or {}).get("declaredCapabilities") or []
        if capability
    }
    missing = sorted(required - set(ids))
    if missing:
        target = f"{image_name} " if image_name else ""
        fail(f"{target}missing declared capability smoke tests: {', '.join(missing)}")

    print(f"smoke-plan-check ok: {image_name or plan_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
