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
jq -e '.version != "pinned" and .source == "nixpkgs.vscode-extensions" and (.sourceLock.ref | length > 0)' "$tmpdir/extension.json" >/dev/null
jq -e '.sourceLock.sha256 and .sourceLock.manifestSha256 and .sourceLock.vsixSha256' "$tmpdir/extension.json" >/dev/null
jq -e '.validation.strategy' "$tmpdir/extension.json" >/dev/null

"$tool/bin/devcontainer-image" explain env PATH --report "$reports_dir" >"$tmpdir/env.json"
jq -e '.sources[0] == "compiler.env.path" and (.pathEntries | length >= 1)' "$tmpdir/env.json" >/dev/null

"$tool/bin/devcontainer-image" explain docker-access --report "$reports_dir" \
  | jq -e 'has("enabled") and has("privilegeReport")' >/dev/null

"$tool/bin/devcontainer-image" explain image-plan --report "$reports_dir" \
  | jq -e --arg image_name "$image_name" '.image == $image_name' >/dev/null

"$tool/bin/devcontainer-image" explain security --report "$reports_dir" \
  | jq -e 'has("remoteTcpUsesTls") and .lifecycleLogRedaction and .extensionArtifactsLocked and .dynamicPackageFreezeReviewable and (.uvxAutoRunFromShellInit | not) and (.npxAutoRunFromShellInit | not)' >/dev/null

if [ "$image_name" = "nix-dind" ]; then
  jq -e '.dockerAccess.enabled and .dockerAccess.privilege.level == "high" and .dockerAccess.remoteTcp.enabled' \
    "$reports_dir/metadata-merged-preview.json" >/dev/null
else
  jq -e 'has("dockerAccess") | not' "$reports_dir/metadata-merged-preview.json" >/dev/null
fi

"$tool/bin/devcontainer-image" check "$reports_dir/metadata-label.json"
"$tool/bin/devcontainer-image" diff "$reports_dir/layer-plan.json" "$reports_dir/layer-plan.json" >"$tmpdir/diff.txt"
jq -e '.added == [] and .removed == [] and .changed == []' "$tmpdir/diff.txt" >/dev/null

jq '.layers[0].priority += 1' "$reports_dir/layer-plan.json" >"$tmpdir/layer-plan-modified.json"
"$tool/bin/devcontainer-image" diff "$reports_dir/layer-plan.json" "$tmpdir/layer-plan-modified.json" >"$tmpdir/diff-changed.txt"
jq -e '.changed | length == 1' "$tmpdir/diff-changed.txt" >/dev/null
jq -e '.changed[0].reasons | index("priority changed")' "$tmpdir/diff-changed.txt" >/dev/null

if "$tool/bin/devcontainer-image" explain package does-not-exist --report "$reports_dir" >"$tmpdir/missing-package.out" 2>"$tmpdir/missing-package.err"; then
  echo "expected explain package to fail for missing package" >&2
  exit 1
fi
grep -q 'package not found: does-not-exist' "$tmpdir/missing-package.err"

if "$tool/bin/devcontainer-image" explain env DOES_NOT_EXIST --report "$reports_dir" >"$tmpdir/missing-env.out" 2>"$tmpdir/missing-env.err"; then
  echo "expected explain env to fail for missing entry" >&2
  exit 1
fi
grep -q 'environment entry not found: DOES_NOT_EXIST' "$tmpdir/missing-env.err"

PATH="" "$tool/bin/devcontainer-image" doctor image "ghcr.io/example/devcontainer-$image_name:latest" >"$tmpdir/doctor.txt"
grep -q 'docker unavailable in current environment' "$tmpdir/doctor.txt"

echo "report-cli-check ok: $image_name"
