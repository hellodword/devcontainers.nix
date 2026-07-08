#!/usr/bin/env python3
import pathlib
import re
import sys

from lib.json_checks import fail as fail_with_prefix
from lib.json_checks import read_json, walk_strings


PREFIX = "report-bundle-check"
SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)


def fail(message: str) -> None:
    fail_with_prefix(PREFIX, message)


def validate_report_names(field_name: str, report_files) -> list[str]:
    if not isinstance(report_files, list) or not all(
        isinstance(report_name, str) and report_name for report_name in report_files
    ):
        fail(f"ci-plan.json {field_name} must be a list of non-empty file names")
    if len(report_files) != len(set(report_files)):
        fail(f"ci-plan.json {field_name} must not contain duplicates")
    if "ci-plan.json" in report_files:
        fail(f"ci-plan.json must not list itself in {field_name}")
    invalid = [
        name
        for name in report_files
        if pathlib.PurePosixPath(name).name != name or pathlib.PurePosixPath(name).suffix != ".json"
    ]
    if invalid:
        fail(f"ci-plan.json {field_name} contains invalid file names: {', '.join(sorted(invalid))}")
    return report_files


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: tests/ci/check-report-bundle.py <reports-dir> <image-name>",
            file=sys.stderr,
        )
        return 1

    reports_dir = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    if not reports_dir.is_dir():
        fail(f"reports directory does not exist: {reports_dir}")

    ci_plan_path = reports_dir / "ci-plan.json"
    if not ci_plan_path.is_file():
        fail("reports directory missing ci-plan.json")

    ci_plan = read_json(ci_plan_path, PREFIX)
    if not isinstance(ci_plan, dict):
        fail("ci-plan.json must be an object")
    if ci_plan.get("image") != image_name:
        fail("ci-plan.json image must match the checked image")
    ci_report_files = validate_report_names("reportFiles", ci_plan.get("reportFiles"))
    non_ci_report_files = validate_report_names("nonCiReportFiles", ci_plan.get("nonCiReportFiles"))
    shared_report_files = sorted(set(ci_report_files).intersection(non_ci_report_files))
    if shared_report_files:
        fail(f"ci-plan.json report file lists must not overlap: {', '.join(shared_report_files)}")

    listed_report_files = set(ci_report_files) | set(non_ci_report_files)
    missing_reports = sorted(report_name for report_name in listed_report_files if not (reports_dir / report_name).is_file())
    if missing_reports:
        fail(f"ci-plan.json lists missing report files: {', '.join(missing_reports)}")

    json_report_files = sorted(path.name for path in reports_dir.glob("*.json"))
    unlisted_reports = sorted(set(json_report_files) - listed_report_files - {"ci-plan.json"})
    if unlisted_reports:
        fail(f"reports directory contains unlisted report files: {', '.join(unlisted_reports)}")

    for report_name in sorted(set(json_report_files) - set(non_ci_report_files)):
        report_data = read_json(reports_dir / report_name, PREFIX)
        for text in walk_strings(report_data):
            if SENSITIVE_VALUE_RE.search(text):
                fail(f"{report_name} appears to contain sensitive material")

    print(f"report-bundle-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
