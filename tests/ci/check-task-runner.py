#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def run(command: list[str], *, env: dict[str, str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(command, env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2), encoding="utf-8")


def main() -> int:
    runner_root = os.environ.get("DEVCONTAINER_RUNNER")
    if not runner_root:
        fail("DEVCONTAINER_RUNNER is required")
    runner = Path(runner_root) / "bin" / "devcontainer-task-runner"
    bash = shutil.which("bash")
    if not bash:
        fail("bash is required for task-runner check")

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        tasks_file = tmpdir / "tasks.json"
        state_home = tmpdir / "tasks-state"
        write_json(
            tasks_file,
            {
                "tasks": [
                    {
                        "name": "redact-test",
                        "phase": "postCreate",
                        "once": True,
                        "user": "vscode",
                        "command": [bash, "-lc", "echo TOKEN=super-secret; echo ok"],
                        "timeoutSeconds": 10,
                        "needs": [],
                    },
                    {
                        "name": "failing-test",
                        "phase": "postStart",
                        "once": False,
                        "user": "vscode",
                        "command": [bash, "-lc", "echo PASSWORD=bad; exit 7"],
                        "timeoutSeconds": 10,
                        "needs": [],
                    },
                ]
            },
        )
        env = os.environ.copy()
        env.update({"DEVCONTAINER_TASKS_FILE": str(tasks_file), "XDG_STATE_HOME": str(state_home)})

        run([str(runner), "run", "postCreate"], env=env)
        run([str(runner), "run", "postCreate"], env=env)

        log_file = state_home / "devcontainer" / "tasks" / "logs" / "redact-test.log"
        status_file = state_home / "devcontainer" / "tasks" / "status" / "redact-test.status"
        if not log_file.is_file() or not status_file.is_file():
            fail("task runner did not write log/status files")
        log_text = log_file.read_text(encoding="utf-8")
        if "[REDACTED]" not in log_text or "super-secret" in log_text:
            fail(f"redaction failed:\n{log_text}")
        if status_file.read_text(encoding="utf-8").strip() != "done":
            fail("once task did not finish with done status")

        failed = run([str(runner), "run", "postStart"], env=env, check=False)
        if failed.returncode != 7:
            fail(f"expected failing task exit 7, got {failed.returncode}")
        failed_status = state_home / "devcontainer" / "tasks" / "status" / "failing-test.status"
        failed_rc = state_home / "devcontainer" / "tasks" / "status" / "failing-test.exit"
        failed_log = state_home / "devcontainer" / "tasks" / "logs" / "failing-test.log"
        if failed_status.read_text(encoding="utf-8").strip() != "failed":
            fail("failing task did not write failed status")
        if failed_rc.read_text(encoding="utf-8").strip() != "7":
            fail("failing task did not write exit code")
        failed_log_text = failed_log.read_text(encoding="utf-8")
        if "[REDACTED]" not in failed_log_text or "PASSWORD=bad" in failed_log_text:
            fail("failing task log redaction failed")

        invalid_tasks = tmpdir / "invalid-tasks.json"
        invalid_state = tmpdir / "invalid-state"
        write_json(
            invalid_tasks,
            {
                "tasks": [
                    {
                        "name": "../escape",
                        "phase": "postCreate",
                        "once": True,
                        "user": "vscode",
                        "command": [bash, "-lc", "true"],
                        "timeoutSeconds": 10,
                        "needs": [],
                    }
                ]
            },
        )
        invalid_env = env.copy()
        invalid_env.update({"DEVCONTAINER_TASKS_FILE": str(invalid_tasks), "XDG_STATE_HOME": str(invalid_state)})
        invalid = run([str(runner), "status"], env=invalid_env, check=False)
        if invalid.returncode == 0:
            fail("expected invalid task name to fail")
        if invalid_state.exists():
            fail("invalid task name should not create state root")

        cycle_tasks = tmpdir / "cycle-tasks.json"
        write_json(
            cycle_tasks,
            {
                "tasks": [
                    {
                        "name": "a",
                        "phase": "postCreate",
                        "once": True,
                        "user": "vscode",
                        "command": [bash, "-lc", "true"],
                        "timeoutSeconds": 10,
                        "needs": ["b"],
                    },
                    {
                        "name": "b",
                        "phase": "postCreate",
                        "once": True,
                        "user": "vscode",
                        "command": [bash, "-lc", "true"],
                        "timeoutSeconds": 10,
                        "needs": ["a"],
                    },
                ]
            },
        )
        cycle_env = env.copy()
        cycle_env["DEVCONTAINER_TASKS_FILE"] = str(cycle_tasks)
        cycle = run([str(runner), "run", "postCreate"], env=cycle_env, check=False)
        if cycle.returncode == 0 or "dependency cycle" not in cycle.stderr:
            fail(f"expected dependency cycle failure, got stderr:\n{cycle.stderr}")

    print("task-runner-check ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
