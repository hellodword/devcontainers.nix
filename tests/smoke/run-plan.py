#!/usr/bin/env python3
import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path


USAGE = """usage: run-smoke-plan [--tag tag ...] <image-ref> <smoke-plan.json>
   or: run-smoke-plan [--tag tag ...] <image-name>
"""

NIX_EXPERIMENTAL_FLAGS = [
    "--extra-experimental-features",
    "nix-command",
    "--extra-experimental-features",
    "flakes",
]


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
        ["nix", *NIX_EXPERIMENTAL_FLAGS, "build", attr, "--print-out-paths", "--no-link"],
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


def shell_argv(script: dict) -> list[str]:
    shell = script["shell"]
    command = script["command"]
    if script["interactive"]:
        return [shell, "-ic", command]
    if os.path.basename(shell) == "bash":
        return [shell, "-lc", command]
    return [shell, "-c", command]


def validate_scripts(test_id: str, scripts) -> str | None:
    if not isinstance(scripts, list) or not scripts:
        return f"{test_id} must include a non-empty scripts array"
    for index, script in enumerate(scripts):
        if not isinstance(script, dict):
            return f"{test_id} script {index} must be an object"
        if not isinstance(script.get("command"), str) or not script["command"]:
            return f"{test_id} script {index} must include a non-empty command"
        if not isinstance(script.get("shell"), str) or not script["shell"]:
            return f"{test_id} script {index} must include a non-empty shell"
        if not isinstance(script.get("interactive"), bool):
            return f"{test_id} script {index} must include an interactive boolean"
    return None


def write_and_print(log_file: Path, text: str, *, stderr: bool = False) -> None:
    log_file.write_text(text, encoding="utf-8")
    print(text, end="", file=sys.stderr if stderr else sys.stdout)


def decode_process_output(output: bytes | str | None) -> str:
    if output is None:
        return ""
    if isinstance(output, bytes):
        return output.decode(errors="replace")
    return output


def remaining_timeout(deadline: float) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise subprocess.TimeoutExpired(["smoke case"], 0)
    return remaining


def run_with_deadline(command: list[str], deadline: float) -> subprocess.CompletedProcess:
    return subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=remaining_timeout(deadline),
    )


def run_test(image_ref: str, test: dict, smoke_log_dir: Path) -> int:
    test_id = test.get("id")
    timeout_seconds = int(test.get("timeoutSeconds", 30))
    scripts = test.get("scripts") or []
    requires = test.get("requires") or []
    log_file = smoke_log_dir / f"{str(test_id).replace('/', '_')}.log"

    script_error = validate_scripts(str(test_id), scripts)
    if script_error is not None:
        text = f"fail {test_id}\nreason={script_error}\n"
        write_and_print(log_file, text, stderr=True)
        return 1

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
    )
    output = header
    container_id = ""
    try:
        deadline = time.monotonic() + timeout_seconds
        create_result = run_with_deadline(["docker", "create", image_ref], deadline)
        if create_result.returncode != 0:
            output += decode_process_output(create_result.stdout)
            log_file.write_text(output, encoding="utf-8")
            print(output, end="")
            return create_result.returncode

        container_id = decode_process_output(create_result.stdout).strip().splitlines()[-1]
        start_result = run_with_deadline(["docker", "start", container_id], deadline)
        if start_result.returncode != 0:
            output += decode_process_output(start_result.stdout)
            log_file.write_text(output, encoding="utf-8")
            print(output, end="")
            return start_result.returncode

        for index, script in enumerate(scripts):
            script_argv = shell_argv(script)
            output += f"script[{index}]={command_line(script_argv)}\n"
            result = run_with_deadline(["docker", "exec", container_id, *script_argv], deadline)
            output += decode_process_output(result.stdout)
            if result.returncode != 0:
                log_file.write_text(output, encoding="utf-8")
                print(output, end="")
                return result.returncode

        log_file.write_text(output, encoding="utf-8")
        print(output, end="")
        return 0
    except subprocess.TimeoutExpired as exc:
        partial = decode_process_output(exc.stdout)
        output += partial + f"timeout after {timeout_seconds}s\n"
        log_file.write_text(output, encoding="utf-8")
        print(output, end="")
        return 124
    finally:
        if container_id:
            try:
                subprocess.run(
                    ["docker", "rm", "-f", container_id],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    timeout=30,
                )
            except subprocess.SubprocessError:
                pass


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
