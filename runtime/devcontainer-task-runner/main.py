#!/usr/bin/env python3
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile
from pathlib import Path


TASKS_FILE = Path(os.environ.get("DEVCONTAINER_TASKS_FILE", "/usr/share/devcontainer/tasks.json"))
HOME = os.environ.get("HOME", "")
STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", str(Path(HOME) / ".local" / "state"))) / "devcontainer" / "tasks"
STATUS_DIR = STATE_ROOT / "status"
LOG_DIR = STATE_ROOT / "logs"

SAFE_TASK_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
CONTROL_RE = re.compile(r"[\x00-\x1f\x7f]")
PREFIX_SECRET_PATTERNS = [
    re.compile(
        r"([A-Za-z0-9_.:/-]*(?:TOKEN|PASSWORD|PASSWD|PWD|SECRET|KEY|API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY|AUTH[_-]?TOKEN|CREDENTIAL|CLIENT[_-]?SECRET)[A-Za-z0-9_.:/-]*=)[^\s]+",
        re.IGNORECASE,
    ),
    re.compile(r"((?:Authorization|Proxy-Authorization):\s*)[\x21-\x7e]+", re.IGNORECASE),
    re.compile(r"(\bsig=)[^&\s;]+", re.IGNORECASE),
    re.compile(r"(\bSharedAccessSignature=)[^\s;]+", re.IGNORECASE),
]
VALUE_SECRET_PATTERNS = [
    re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bnpm_[A-Za-z0-9]{30,}\b"),
    re.compile(r"\b(?:A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    re.compile(r"\bya29\.[0-9A-Za-z_-]+\b"),
]
TIMEOUT_EXIT_CODE = 124
TERMINATION_GRACE_SECONDS = 2

USAGE = """devcontainer-task-runner run <phase>
devcontainer-task-runner plan <phase>
devcontainer-task-runner list
devcontainer-task-runner status
devcontainer-task-runner logs <task>
devcontainer-task-runner reset <task>
devcontainer-task-runner ensure-xdg
"""


def usage(file=sys.stdout):
    print(USAGE, end="", file=file)


def fail(message: str) -> None:
    print(redact(message), file=sys.stderr)
    raise SystemExit(1)


def safe_task_name(name) -> bool:
    return (
        isinstance(name, str)
        and bool(name)
        and "/" not in name
        and "\\" not in name
        and ".." not in name
        and CONTROL_RE.search(name) is None
        and SAFE_TASK_RE.fullmatch(name) is not None
    )


def validate_task_name(name) -> None:
    if not safe_task_name(name):
        fail(f"invalid task name: {name!r}")


def load_tasks() -> dict[str, dict]:
    if not TASKS_FILE.is_file():
        fail(f"tasks file not found: {TASKS_FILE}")
    with TASKS_FILE.open("r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            fail(f"invalid tasks file JSON: {exc}")
    tasks = data.get("tasks") if isinstance(data, dict) else None
    if not isinstance(tasks, list):
        fail("tasks file must contain a tasks array")

    by_name = {}
    for task in tasks:
        if not isinstance(task, dict):
            fail("each task must be an object")
        name = task.get("name")
        validate_task_name(name)
        if name in by_name:
            fail(f"duplicate task name: {name}")
        phase = task.get("phase")
        if not isinstance(phase, str) or not phase:
            fail(f"task {name} must include a non-empty phase")
        once = task.get("once")
        if not isinstance(once, bool):
            fail(f"task {name} must include a boolean once value")
        command = task.get("command")
        if not isinstance(command, list) or not all(isinstance(part, str) and part for part in command):
            fail(f"task {name} must include a command array of non-empty strings")
        needs = task.get("needs", [])
        if not isinstance(needs, list) or not all(isinstance(dep, str) and dep for dep in needs):
            fail(f"task {name} must include a needs array")
        for dep in needs:
            validate_task_name(dep)
        timeout = task.get("timeoutSeconds", 60)
        if not isinstance(timeout, int) or isinstance(timeout, bool) or timeout < 1:
            fail(f"task {name} must include a positive timeoutSeconds value")
        user = task.get("user", "vscode")
        if user != "vscode":
            fail(f"task {name} has unsupported user: {user}")
        by_name[name] = task

    for name, task in by_name.items():
        for dep in task.get("needs", []):
            if dep not in by_name:
                fail(f"task {name} depends on unknown task: {dep}")
    validate_acyclic(by_name)
    return by_name


def validate_acyclic(tasks: dict[str, dict]) -> None:
    visiting = set()
    visited = set()
    stack = []

    def visit(name: str):
        if name in visited:
            return
        if name in visiting:
            cycle = stack[stack.index(name) :] + [name]
            fail(f"task dependency cycle: {' -> '.join(cycle)}")
        visiting.add(name)
        stack.append(name)
        for dep in tasks[name].get("needs", []):
            visit(dep)
        stack.pop()
        visiting.remove(name)
        visited.add(name)

    for name in sorted(tasks):
        visit(name)


def ensure_state_dirs() -> None:
    STATUS_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(text)
        tmp_name = handle.name
    os.replace(tmp_name, path)


def redact(text: str) -> str:
    for pattern in PREFIX_SECRET_PATTERNS:
        text = pattern.sub(lambda match: f"{match.group(1)}[REDACTED]", text)
    for pattern in VALUE_SECRET_PATTERNS:
        text = pattern.sub("[REDACTED]", text)
    return text


def task_paths(name: str) -> tuple[Path, Path, Path]:
    validate_task_name(name)
    return LOG_DIR / f"{name}.log", STATUS_DIR / f"{name}.status", STATUS_DIR / f"{name}.exit"


def status_value(path: Path, default: str) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return default


def shell_command_line(command: list[str]) -> str:
    return "".join(f"{shlex.quote(part)} " for part in command)


def terminate_process_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=TERMINATION_GRACE_SECONDS)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def run_command(command: list[str], timeout_seconds: int) -> tuple[str, int, bool]:
    proc = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, _ = proc.communicate(timeout=timeout_seconds)
        return stdout or "", proc.returncode, False
    except subprocess.TimeoutExpired:
        terminate_process_group(proc)
        stdout, _ = proc.communicate()
        return stdout or "", TIMEOUT_EXIT_CODE, True


def run_task(name: str, tasks: dict[str, dict], active: set[str] | None = None) -> int:
    if active is None:
        active = set()
    if name in active:
        fail(f"task dependency cycle while running: {name}")
    task = tasks.get(name)
    if task is None:
        fail(f"unknown task: {name}")
    active.add(name)

    logfile, statusfile, rcfile = task_paths(name)
    if task.get("once") is True and statusfile.is_file() and status_value(statusfile, "") == "done":
        active.remove(name)
        return 0

    for dep in task.get("needs", []):
        rc = run_task(dep, tasks, active)
        if rc != 0:
            active.remove(name)
            return rc

    command = task.get("command") or []
    if not command:
        atomic_write(logfile, "")
        atomic_write(statusfile, "skipped\n")
        atomic_write(rcfile, "0\n")
        active.remove(name)
        return 0

    timeout = task.get("timeoutSeconds", 60)
    log_text = f"task={name} phase={task['phase']}\ncommand={shell_command_line(command)}\n"
    output, returncode, timed_out = run_command(command, timeout)
    log_text += output
    if timed_out:
        diagnostic = f"task {name} timed out after {timeout} seconds\n"
        print(diagnostic, end="", file=sys.stderr)
        if not log_text.endswith("\n"):
            log_text += "\n"
        log_text += diagnostic
    atomic_write(logfile, redact(log_text))
    if returncode == 0:
        atomic_write(statusfile, "done\n")
        atomic_write(rcfile, "0\n")
    else:
        atomic_write(statusfile, "failed\n")
        atomic_write(rcfile, f"{returncode}\n")
    active.remove(name)
    return returncode


def ensure_xdg() -> None:
    home = os.environ.get("HOME")
    defaults = {
        "XDG_CONFIG_HOME": ".config",
        "XDG_CACHE_HOME": ".cache",
        "XDG_DATA_HOME": ".local/share",
        "XDG_STATE_HOME": ".local/state",
    }
    for env_name, suffix in defaults.items():
        configured = os.environ.get(env_name)
        if configured:
            path = Path(configured)
        elif home:
            path = Path(home) / suffix
        else:
            fail(f"HOME or {env_name} is required")
        path.mkdir(parents=True, exist_ok=True)


def cmd_list(tasks: dict[str, dict]) -> int:
    for name in sorted(tasks):
        task = tasks[name]
        print(f"{name}\t{task['phase']}\tonce={str(task['once']).lower()}")
    return 0


def cmd_status(tasks: dict[str, dict]) -> int:
    for name in sorted(tasks):
        _, statusfile, rcfile = task_paths(name)
        status = status_value(statusfile, "pending")
        rc = status_value(rcfile, "-")
        print(f"{name}\t{status}\texit={rc}")
    return 0


def phase_roots(tasks: dict[str, dict], phase: str) -> list[str]:
    return [name for name in sorted(tasks) if tasks[name].get("phase") == phase]


def topo_order(tasks: dict[str, dict], roots: list[str]) -> list[str]:
    visited = set()
    order = []

    def visit(name: str) -> None:
        if name in visited:
            return
        for dep in tasks[name].get("needs", []):
            visit(dep)
        visited.add(name)
        order.append(name)

    for root in roots:
        visit(root)
    return order


def dependency_tree(tasks: dict[str, dict], name: str) -> dict:
    return {
        "name": name,
        "needs": [dependency_tree(tasks, dep) for dep in tasks[name].get("needs", [])],
    }


def plan_task(tasks: dict[str, dict], name: str) -> dict:
    task = tasks[name]
    _, statusfile, rcfile = task_paths(name)
    status = status_value(statusfile, "pending")
    exit_code = status_value(rcfile, "-")
    once_done = task["once"] is True and status == "done"
    has_command = bool(task.get("command") or [])
    skip_reason = None
    if once_done:
        skip_reason = "once-done"
    elif not has_command:
        skip_reason = "empty-command"
    return {
        "name": name,
        "phase": task["phase"],
        "needs": task.get("needs", []),
        "once": task["once"],
        "status": status,
        "exit": exit_code,
        "timeoutSeconds": task["timeoutSeconds"],
        "hasCommand": has_command,
        "wouldRun": skip_reason is None,
        "skipReason": skip_reason,
    }


def cmd_plan(tasks: dict[str, dict], args: list[str]) -> int:
    if len(args) != 1 or not args[0]:
        usage(sys.stderr)
        return 1
    phase = args[0]
    roots = phase_roots(tasks, phase)
    order = topo_order(tasks, roots)
    plan = {
        "phase": phase,
        "topoOrder": order,
        "roots": [dependency_tree(tasks, root) for root in roots],
        "tasks": [plan_task(tasks, name) for name in order],
    }
    print(json.dumps(plan, indent=2, sort_keys=True))
    return 0


def cmd_logs(tasks: dict[str, dict], args: list[str]) -> int:
    if len(args) != 1:
        usage(sys.stderr)
        return 1
    task = args[0]
    if task not in tasks:
        fail(f"unknown task: {task}")
    logfile, _, _ = task_paths(task)
    sys.stdout.write(logfile.read_text(encoding="utf-8"))
    return 0


def cmd_reset(tasks: dict[str, dict], args: list[str]) -> int:
    if len(args) != 1:
        usage(sys.stderr)
        return 1
    task = args[0]
    if task not in tasks:
        fail(f"unknown task: {task}")
    for path in task_paths(task):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    return 0


def cmd_run(tasks: dict[str, dict], args: list[str]) -> int:
    if len(args) != 1 or not args[0]:
        usage(sys.stderr)
        return 1
    ensure_state_dirs()
    phase = args[0]
    for name in sorted(tasks):
        if tasks[name].get("phase") == phase:
            rc = run_task(name, tasks)
            if rc != 0:
                return rc
    return 0


def main(argv: list[str]) -> int:
    cmd = argv[0] if argv else ""
    args = argv[1:]
    if cmd == "ensure-xdg":
        ensure_xdg()
        return 0
    if cmd not in {"list", "status", "logs", "reset", "run", "plan"}:
        usage(sys.stderr)
        return 1
    tasks = load_tasks()
    if cmd == "list":
        return cmd_list(tasks)
    if cmd == "status":
        return cmd_status(tasks)
    if cmd == "plan":
        return cmd_plan(tasks, args)
    if cmd == "logs":
        return cmd_logs(tasks, args)
    if cmd == "reset":
        return cmd_reset(tasks, args)
    if cmd == "run":
        return cmd_run(tasks, args)
    usage(sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
