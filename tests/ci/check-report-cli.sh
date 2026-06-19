#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: tests/ci/check-report-cli.sh <devcontainer-image> <reports-dir> <image-name>" >&2
  exit 1
fi

tool="$1"
reports_dir="$2"
image_name="$3"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

package_name="$(jq -r '.packages[0]' "$reports_dir/closure-report.json")"
extension_id="$(jq -r '.extensions[0].id' "$reports_dir/extensions-index.json")"

"$tool/bin/devcontainer-image" explain layer 0 --report "$reports_dir" \
  | jq -e '.group and (.members | length >= 1)' >/dev/null

"$tool/bin/devcontainer-image" explain package "$package_name" --report "$reports_dir" \
  | jq -er '.' >/dev/null

"$tool/bin/devcontainer-image" explain extension "$extension_id" --report "$reports_dir" >"$tmpdir/extension.json"
jq -e --arg extension_id "$extension_id" '.id == $extension_id' "$tmpdir/extension.json" >/dev/null

"$tool/bin/devcontainer-image" explain docker-access --report "$reports_dir" \
  | jq -e 'has("enabled") and has("privilegeReport")' >/dev/null

"$tool/bin/devcontainer-image" explain image-plan --report "$reports_dir" \
  | jq -e --arg image_name "$image_name" '.image == $image_name' >/dev/null

"$tool/bin/devcontainer-image" explain security --report "$reports_dir" \
  | jq -e '.remoteTcpRequiresTls and .lifecycleLogRedaction' >/dev/null

"$tool/bin/devcontainer-image" check "$reports_dir/metadata-label.json"
"$tool/bin/devcontainer-image" diff "$reports_dir/layer-plan.json" "$reports_dir/layer-plan.json" >"$tmpdir/diff.txt"

if "$tool/bin/devcontainer-image" explain package does-not-exist --report "$reports_dir" >"$tmpdir/missing-package.out" 2>"$tmpdir/missing-package.err"; then
  echo "expected explain package to fail for missing package" >&2
  exit 1
fi
grep -q 'package not found: does-not-exist' "$tmpdir/missing-package.err"

PATH="" "$tool/bin/devcontainer-image" doctor image "ghcr.io/example/devcontainer-$image_name:latest" >"$tmpdir/doctor.txt"
grep -q 'docker unavailable in current environment' "$tmpdir/doctor.txt"

echo "report-cli-check ok: $image_name"
