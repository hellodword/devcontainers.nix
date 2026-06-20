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
    names = [test.get("name") for test in tests]
    if len(names) != len(set(names)):
        fail("smoke-test-plan.json must not contain duplicate test names")

    required = {
        test.get("name")
        for test in (profile_report.get("tests") or {}).get("smoke") or []
        if test.get("name")
    }
    missing = sorted(required - set(names))
    if missing:
        target = f"{image_name} " if image_name else ""
        fail(f"{target}missing profile smoke tests: {', '.join(missing)}")

    print(f"smoke-plan-check ok: {image_name or plan_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
