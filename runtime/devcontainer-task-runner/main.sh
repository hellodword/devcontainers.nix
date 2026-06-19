set -euo pipefail

tasks_file="${DEVCONTAINER_TASKS_FILE:-/usr/share/devcontainer/tasks.json}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/devcontainer/tasks"
status_dir="$state_root/status"
log_dir="$state_root/logs"

mkdir -p "$status_dir" "$log_dir"

usage() {
  cat <<'EOF'
devcontainer-task-runner run <phase>
devcontainer-task-runner list
devcontainer-task-runner status
devcontainer-task-runner logs <task>
devcontainer-task-runner reset <task>
devcontainer-task-runner ensure-xdg
EOF
}

ensure_tasks_file() {
  if [ ! -f "$tasks_file" ]; then
    echo "tasks file not found: $tasks_file" >&2
    exit 1
  fi
}

ensure_xdg() {
  mkdir -p \
    "${XDG_CONFIG_HOME:-$HOME/.config}" \
    "${XDG_CACHE_HOME:-$HOME/.cache}" \
    "${XDG_DATA_HOME:-$HOME/.local/share}" \
    "${XDG_STATE_HOME:-$HOME/.local/state}"
}

redact_log_file() {
  local logfile="$1"
  sed -E -i \
    -e 's/([A-Za-z0-9_]*(TOKEN|PASSWORD|SECRET|KEY)[A-Za-z0-9_]*=)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's/(Authorization: )[[:graph:]]+/\1[REDACTED]/g' \
    "$logfile"
}

task_field() {
  local name="$1"
  local expr="$2"
  jq -r --arg name "$name" ".tasks[] | select(.name == \$name) | $expr" "$tasks_file"
}

run_task() {
  local name="$1"
  local once
  local phase
  local logfile
  local statusfile
  local rcfile

  once="$(task_field "$name" '.once')"
  phase="$(task_field "$name" '.phase')"
  logfile="$log_dir/$name.log"
  statusfile="$status_dir/$name.status"
  rcfile="$status_dir/$name.exit"

  if [ "$once" = "true" ] && [ -f "$statusfile" ] && [ "$(cat "$statusfile")" = "done" ]; then
    return 0
  fi

  while IFS= read -r dep; do
    [ -n "$dep" ] || continue
    run_task "$dep"
  done < <(task_field "$name" '.needs[]?')

  mapfile -t command_parts < <(task_field "$name" '.command[]')
  : >"$logfile"
  if [ "${#command_parts[@]}" -eq 0 ]; then
    echo "skipped" >"$statusfile"
    echo "0" >"$rcfile"
    return 0
  fi

  {
    printf 'task=%s phase=%s\n' "$name" "$phase"
    printf 'command='
    printf '%q ' "${command_parts[@]}"
    printf '\n'
  } >>"$logfile"

  if "${command_parts[@]}" >>"$logfile" 2>&1; then
    redact_log_file "$logfile"
    echo "done" >"$statusfile"
    echo "0" >"$rcfile"
  else
    local rc=$?
    redact_log_file "$logfile"
    echo "failed" >"$statusfile"
    echo "$rc" >"$rcfile"
    return "$rc"
  fi
}

cmd="${1:-}"
case "$cmd" in
  list)
    ensure_tasks_file
    jq -r '.tasks[] | "\(.name)\t\(.phase)\tonce=\(.once)"' "$tasks_file"
    ;;
  status)
    ensure_tasks_file
    jq -r '.tasks[] | .name' "$tasks_file" | while IFS= read -r name; do
      status="pending"
      rc="-"
      [ -f "$status_dir/$name.status" ] && status="$(cat "$status_dir/$name.status")"
      [ -f "$status_dir/$name.exit" ] && rc="$(cat "$status_dir/$name.exit")"
      printf '%s\t%s\texit=%s\n' "$name" "$status" "$rc"
    done
    ;;
  logs)
    ensure_tasks_file
    task="${2:-}"
    [ -n "$task" ] || { usage >&2; exit 1; }
    cat "$log_dir/$task.log"
    ;;
  reset)
    ensure_tasks_file
    task="${2:-}"
    [ -n "$task" ] || { usage >&2; exit 1; }
    rm -f "$status_dir/$task.status" "$status_dir/$task.exit" "$log_dir/$task.log"
    ;;
  run)
    ensure_tasks_file
    phase="${2:-}"
    [ -n "$phase" ] || { usage >&2; exit 1; }
    jq -r --arg phase "$phase" '.tasks[] | select(.phase == $phase) | .name' "$tasks_file" | while IFS= read -r task; do
      run_task "$task"
    done
    ;;
  ensure-xdg)
    ensure_xdg
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
