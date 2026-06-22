#!/usr/bin/env python3
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path


USAGE = """usage: run-smoke-plan [--tag tag ...] <image-ref> <smoke-plan.json>
   or: run-smoke-plan [--tag tag ...] <image-name>
"""


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_args(argv: list[str]) -> tuple[list[str], str, str | None]:
    tags = []
    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--tag":
            if index + 1 >= len(argv):
                fail("--tag requires a value")
            tags.append(argv[index + 1])
            index += 2
        elif arg in {"--help", "-h"}:
            print(USAGE, end="", file=sys.stderr)
            raise SystemExit(0)
        elif arg.startswith("--"):
            fail(f"unknown option: {arg}")
        else:
            break
    rest = argv[index:]
    if not rest:
        print(USAGE, end="", file=sys.stderr)
        raise SystemExit(1)
    if len(rest) > 2:
        print(USAGE, end="", file=sys.stderr)
        raise SystemExit(1)
    return tags, rest[0], rest[1] if len(rest) == 2 else None


def nix_build(attr: str) -> str:
    result = subprocess.run(
        ["nix", "build", attr, "--print-out-paths", "--no-link"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    return result.stdout.strip().splitlines()[-1]


def read_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def selected_tests(plan: dict, required_tags: list[str]):
    for test in plan.get("tests") or []:
        case_tags = test.get("tags") or []
        if all(tag in case_tags for tag in required_tags):
            yield test


def command_line(parts: list[str]) -> str:
    return "".join(f"{shlex.quote(part)} " for part in parts)


def write_and_print(log_file: Path, text: str, *, stderr: bool = False) -> None:
    log_file.write_text(text, encoding="utf-8")
    print(text, end="", file=sys.stderr if stderr else sys.stdout)


def run_test(image_ref: str, test: dict, smoke_log_dir: Path) -> int:
    test_id = test.get("id")
    timeout_seconds = int(test.get("timeoutSeconds", 30))
    command = test.get("command") or []
    requires = test.get("requires") or []
    log_file = smoke_log_dir / f"{str(test_id).replace('/', '_')}.log"

    if not command:
        print(f"skip {test_id}")
        log_file.write_text(f"skip {test_id}\nreason=empty command\n", encoding="utf-8")
        return 0

    for requirement in requires:
        text = f"fail {test_id}\nunsupported requirement={requirement}\n"
        write_and_print(log_file, text, stderr=True)
        return 1

    print(f"==> {test_id}")
    header = (
        f"image={image_ref}\n"
        f"id={test_id}\n"
        f"tags={json.dumps(test.get('tags'))}\n"
        f"requires={json.dumps(test.get('requires'))}\n"
        f"timeoutSeconds={timeout_seconds}\n"
        f"command={command_line(command)}\n"
    )
    docker_command = ["docker", "run", "--rm", "--entrypoint", command[0], image_ref, *command[1:]]
    try:
        result = subprocess.run(
            docker_command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout_seconds,
        )
        output = header + (result.stdout or "")
        log_file.write_text(output, encoding="utf-8")
        print(output, end="")
        return result.returncode
    except subprocess.TimeoutExpired as exc:
        partial = exc.stdout or ""
        if isinstance(partial, bytes):
            partial = partial.decode(errors="replace")
        output = header + partial + f"timeout after {timeout_seconds}s\n"
        log_file.write_text(output, encoding="utf-8")
        print(output, end="")
        return 124


def main(argv: list[str]) -> int:
    tags, target, plan_file_arg = parse_args(argv)
    smoke_log_dir = Path(os.environ.get("SMOKE_LOG_DIR", "smoke-logs"))

    if plan_file_arg is None:
        image_name = target
        ci_plan_path = Path(nix_build(f".#images.{image_name}.ci-plan-json"))
        image_ref = read_json(ci_plan_path)["imageRef"]
        plan_file = Path(nix_build(f".#images.{image_name}.smoke"))
    else:
        image_ref = target
        plan_file = Path(plan_file_arg)

    if not plan_file.is_file():
        fail(f"smoke plan not found: {plan_file}")

    smoke_log_dir.mkdir(parents=True, exist_ok=True)
    plan = read_json(plan_file)
    for test in selected_tests(plan, tags):
        rc = run_test(image_ref, test, smoke_log_dir)
        if rc != 0:
            return rc
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
