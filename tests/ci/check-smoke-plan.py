#!/usr/bin/env python3
import json
import pathlib
import sys

CAPABILITY_FIELD_SUFFIX = "Capabilities"
OLD_PROFILE_TEST_FIELDS = {
    f"declared{CAPABILITY_FIELD_SUFFIX}",
    f"resolved{CAPABILITY_FIELD_SUFFIX}",
}


def fail(message: str):
    print(f"smoke-plan-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def validate_smoke_plan_schema(plan):
    if "capabilities" in plan:
        fail("smoke-test-plan.json must not contain capabilities")

    tests = plan.get("tests")
    if not isinstance(tests, list) or not tests:
        fail("smoke-test-plan.json must include a non-empty tests array")
    if not all(isinstance(test, dict) for test in tests):
        fail("smoke-test-plan.json tests must contain objects")

    case_ids = plan.get("caseIds")
    if not isinstance(case_ids, list) or not case_ids:
        fail("smoke-test-plan.json must include a non-empty caseIds array")
    if not all(isinstance(case_id, str) and case_id for case_id in case_ids):
        fail("smoke-test-plan.json caseIds must contain non-empty strings")
    if len(case_ids) != len(set(case_ids)):
        fail("smoke-test-plan.json caseIds must not contain duplicates")

    ids = [test.get("id") for test in tests]
    if not all(isinstance(test_id, str) and test_id for test_id in ids):
        fail("each smoke test must include a non-empty id")
    expected_case_ids = sorted(set(ids))
    if case_ids != expected_case_ids:
        fail("smoke-test-plan.json caseIds must equal sorted unique test ids")

    return tests, ids


def validate_profile_report_schema(profile_report):
    tests = profile_report.get("tests") or {}
    if OLD_PROFILE_TEST_FIELDS.intersection(tests):
        fail("profile-report.json tests must not contain capability fields")


def validate_smoke_scripts(test_id, test):
    scripts = test.get("scripts")
    if not isinstance(scripts, list) or not scripts:
        fail(f"{test_id} must include a non-empty scripts array")
    for index, script in enumerate(scripts):
        if not isinstance(script, dict):
            fail(f"{test_id} script {index} must be an object")
        if not isinstance(script.get("command"), str) or not script["command"]:
            fail(f"{test_id} script {index} must include a non-empty command")
        if not isinstance(script.get("shell"), str) or not script["shell"]:
            fail(f"{test_id} script {index} must include a non-empty shell")
        if not isinstance(script.get("interactive"), bool):
            fail(f"{test_id} script {index} must include an interactive boolean")


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

    validate_profile_report_schema(profile_report)
    tests, ids = validate_smoke_plan_schema(plan)
    if len(ids) != len(set(ids)):
        fail("smoke-test-plan.json must not contain duplicate test ids")
    for test in tests:
        test_id = test.get("id")
        if not isinstance(test_id, str) or not test_id:
            fail("each smoke test must include a non-empty id")
        if not isinstance(test.get("tags"), list) or not all(isinstance(tag, str) and tag for tag in test["tags"]):
            fail(f"{test_id} must include string tags")
        validate_smoke_scripts(test_id, test)
        if not isinstance(test.get("requires"), list) or not all(
            isinstance(requirement, str) and requirement for requirement in test["requires"]
        ):
            fail(f"{test_id} must include a requires array")
        if not isinstance(test.get("timeoutSeconds"), int) or test["timeoutSeconds"] < 1:
            fail(f"{test_id} must include a positive timeoutSeconds value")

    required = {case for case in (profile_report.get("tests") or {}).get("declaredCases") or [] if case}
    missing = sorted(required - set(ids))
    if missing:
        target = f"{image_name} " if image_name else ""
        fail(f"{target}missing declared smoke cases: {', '.join(missing)}")

    print(f"smoke-plan-check ok: {image_name or plan_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
