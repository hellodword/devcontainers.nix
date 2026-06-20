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
(
  export HOME="$project_root/home"
  export XDG_CONFIG_HOME="$project_root/config"
  export XDG_DATA_HOME="$project_root/data"
  export XDG_STATE_HOME="$project_root/state"
  export DEVPKG_RUNTIME_LIBRARY_PROFILE="$project_root/runtime-libraries/profile"
  export DEVPKG_BUILD_LIBRARY_PROFILE="$project_root/build-libraries/profile"
  export PATH="$HOME/.nix-profile/bin:$XDG_DATA_HOME/nix-profile/bin:$PATH"
  export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

  "$devpkg/bin/devpkg" add cowsay
  "$devpkg/bin/devpkg" list >"$tmpdir/devpkg-list.txt"
  grep -q '^cowsay[[:space:]]' "$tmpdir/devpkg-list.txt"
  grep -q 'legacyPackages\..*\.cowsay$' "$tmpdir/devpkg-list.txt"
  command -v cowsay >/dev/null
  cowsay runtime-tools >"$tmpdir/cowsay.txt"
  grep -q 'runtime-tools' "$tmpdir/cowsay.txt"
  "$devpkg/bin/devpkg" remove cowsay
  test -z "$("$devpkg/bin/devpkg" list)"

  "$devpkg/bin/devpkg" add-lib zlib
  "$devpkg/bin/devpkg" list-lib >"$tmpdir/devpkg-list-lib.txt"
  grep -q '^zlib[[:space:]]' "$tmpdir/devpkg-list-lib.txt"
  grep -q 'legacyPackages\..*\.zlib' "$tmpdir/devpkg-list-lib.txt"
  test -e "$DEVPKG_RUNTIME_LIBRARY_PROFILE/lib/libz.so"
  test ! -e "$DEVPKG_RUNTIME_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-lib zlib
  test -z "$("$devpkg/bin/devpkg" list-lib)"

  "$devpkg/bin/devpkg" add-dev-lib zlib
  "$devpkg/bin/devpkg" list-dev-lib >"$tmpdir/devpkg-list-dev-lib.txt"
  grep -q '^zlib[[:space:]]' "$tmpdir/devpkg-list-dev-lib.txt"
  grep -q 'legacyPackages\..*\.zlib' "$tmpdir/devpkg-list-dev-lib.txt"
  grep -q 'dev,out' "$tmpdir/devpkg-list-dev-lib.txt"
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/lib/libz.so"
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-dev-lib zlib
  test -z "$("$devpkg/bin/devpkg" list-dev-lib)"

  "$devpkg/bin/devpkg" add-dev-lib --outputs out,dev zlib
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-dev-lib zlib

  "$devpkg/bin/devpkg" add-dev-lib --raw "$DEVPKG_NIXPKGS_REF#zlib^out,dev"
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-dev-lib zlib
)

echo "runtime-tools-check ok"
