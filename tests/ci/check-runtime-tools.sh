#!/usr/bin/env bash
set -euo pipefail

flake_ref="${DEVCONTAINER_FLAKE:-.}"
projector="${DEVCONTAINER_PROJECTOR:-$(nix build "$flake_ref#vscode-extension-projector" --print-out-paths --no-link)}"
runner="${DEVCONTAINER_RUNNER:-$(nix build "$flake_ref#devcontainer-task-runner" --print-out-paths --no-link)}"
devpkg="${DEVCONTAINER_DEVPKG:-$(nix build "$flake_ref#devpkg" --print-out-paths --no-link)}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

source_ext_link="$tmpdir/source-ext-link"
source_ext_copy="$tmpdir/source-ext-copy"
symlink_target="$tmpdir/TOKEN=super-secret/target-symlink/extensions"
copy_target="$tmpdir/SECRET=another-secret/target-copy/extensions"
mkdir -p "$source_ext_link" "$source_ext_copy" "$symlink_target" "$copy_target"

cat >"$source_ext_link/package.json" <<'EOF'
{
  "name": "example.extension",
  "publisher": "example",
  "version": "0.0.0"
}
EOF

cat >"$source_ext_copy/package.json" <<'EOF'
{
  "name": "example.native",
  "publisher": "example",
  "version": "0.0.0"
}
EOF

cat >"$tmpdir/index.json" <<EOF
{
  "projectionTargets": [
    "$symlink_target",
    "$copy_target"
  ],
  "extensions": [
    {
      "id": "example.extension",
      "path": "$source_ext_link",
      "projection": "symlink"
    },
    {
      "id": "example.native",
      "path": "$source_ext_copy",
      "projection": "copy-if-needed"
    }
  ]
}
EOF

projector_log="$tmpdir/projector.log"
"$projector/bin/vscode-extension-projector" activate --index "$tmpdir/index.json" >"$projector_log"

test -L "$symlink_target/$(basename "$source_ext_link")"
test -d "$copy_target/$(basename "$source_ext_copy")"
grep -q '\[REDACTED\]' "$projector_log"
! grep -q 'super-secret' "$projector_log"
! grep -q 'another-secret' "$projector_log"

mkdir -p "$tmpdir/tasks-state"
cat >"$tmpdir/tasks.json" <<'EOF'
{
  "tasks": [
    {
      "name": "redact-test",
      "phase": "postCreate",
      "once": true,
      "command": ["bash", "-lc", "echo TOKEN=super-secret; echo ok"]
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

project_root="$tmpdir/project"
mkdir -p "$project_root"
(
  cd "$project_root"
  "$devpkg/bin/devpkg" project init
  "$devpkg/bin/devpkg" freeze --scope project >"$tmpdir/project-freeze.nix"
)
"$devpkg/bin/devpkg" freeze --scope user >"$tmpdir/user-freeze.nix"
grep -q '^{ pkgs }:' "$tmpdir/project-freeze.nix"
grep -q '^{ pkgs }:' "$tmpdir/user-freeze.nix"

echo "runtime-tools-check ok"
