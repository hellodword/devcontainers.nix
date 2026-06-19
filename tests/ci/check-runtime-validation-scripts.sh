#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-.}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

bash -n "$repo_root/tests/smoke/run-plan.sh"
bash -n "$repo_root/tests/smoke/collect-runtime-evidence.sh"

bash "$repo_root/tests/smoke/collect-runtime-evidence.sh" --help >"$tmpdir/help.txt"
grep -q 'collect-runtime-evidence.sh oci' "$tmpdir/help.txt"
grep -q 'collect-runtime-evidence.sh full' "$tmpdir/help.txt"
grep -q 'DOCKER_HOST=tcp://' "$tmpdir/help.txt"

echo "runtime-validation-scripts ok"
