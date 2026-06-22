#!/usr/bin/env bash
set -euo pipefail

runner="${DEVCONTAINER_RUNNER:?DEVCONTAINER_RUNNER is required}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
bash_bin="$(command -v bash)"

mkdir -p "$tmpdir/tasks-state"
cat >"$tmpdir/tasks.json" <<EOF
{
  "tasks": [
    {
      "name": "redact-test",
      "phase": "postCreate",
      "once": true,
      "command": ["$bash_bin", "-lc", "echo TOKEN=super-secret; echo ok"]
    }
  ]
}
EOF

export DEVCONTAINER_TASKS_FILE="$tmpdir/tasks.json"
export XDG_STATE_HOME="$tmpdir/tasks-state"
"$runner/bin/devcontainer-task-runner" run postCreate
"$runner/bin/devcontainer-task-runner" run postCreate

log_file="$tmpdir/tasks-state/devcontainer/tasks/logs/redact-test.log"
status_file="$tmpdir/tasks-state/devcontainer/tasks/status/redact-test.status"

test -f "$log_file"
test -f "$status_file"
grep -q '\[REDACTED\]' "$log_file"
! grep -q 'super-secret' "$log_file"
grep -q '^done$' "$status_file"

echo "task-runner-check ok"
