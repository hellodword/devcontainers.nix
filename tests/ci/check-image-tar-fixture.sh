#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-.}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

reports_dir="$tmpdir/reports"
mkdir -p "$reports_dir"

write_layer_plan() {
  local max_layer_size="$1"
  cat >"$reports_dir/layer-plan.json" <<EOF
{
  "budget": {
    "strategy": "balanced",
    "max": 100,
    "reserve": 20,
    "maxLayerSize": "$max_layer_size"
  },
  "layers": []
}
EOF
}

cat >"$tmpdir/image.json" <<'EOF'
{
  "version": 1,
  "arch": "amd64",
  "image-config": {
    "User": "vscode",
    "WorkingDir": "/workspaces",
    "Entrypoint": ["/usr/bin/devcontainer-entrypoint"],
    "Env": [
      "HOME=/home/vscode",
      "XDG_CONFIG_HOME=/home/vscode/.config",
      "XDG_CACHE_HOME=/home/vscode/.cache",
      "XDG_DATA_HOME=/home/vscode/.local/share",
      "XDG_STATE_HOME=/home/vscode/.local/state",
      "XDG_RUNTIME_DIR=/run/user/1000",
      "LANG=en_US.UTF-8",
      "LANGUAGE=en_US:en",
      "LOCALE_ARCHIVE=/nix/store/fixture-glibc-locales/lib/locale/locale-archive",
      "XDG_CONFIG_DIRS=/etc/xdg",
      "XDG_DATA_DIRS=/usr/local/share:/usr/share",
      "NIXPKGS_CONFIG=/etc/nixpkgs/config.nix",
      "NIXPKGS_ALLOW_UNFREE=1",
      "NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1",
      "NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1",
      "DEVPKG_NIXPKGS_REF=path:/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source",
      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
      "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
      "CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt",
      "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt",
      "TZDIR=/etc/zoneinfo"
    ],
    "Labels": {
      "devcontainer.metadata": "[]"
    }
  },
  "layers": [
    {
      "digest": "sha256:fixture",
      "size": 2048,
      "diff_ids": "sha256:fixture",
      "mediatype": "application/vnd.oci.image.layer.v1.tar",
      "History": {
        "created_by": "fixture layer"
      }
    }
  ]
}
EOF

write_layer_plan "8GiB"
python3 "$repo_root/tests/ci/check-image-tar.py" "$tmpdir/image.json" "$reports_dir" fixture >"$tmpdir/pass.out"
grep -q 'image-artifact-check ok: fixture' "$tmpdir/pass.out"

write_layer_plan "1KiB"
if python3 "$repo_root/tests/ci/check-image-tar.py" "$tmpdir/image.json" "$reports_dir" fixture >"$tmpdir/fail.out" 2>"$tmpdir/fail.err"; then
  echo "expected oversized layer validation to fail" >&2
  exit 1
fi
grep -q 'exceeds max layer size 1024 B' "$tmpdir/fail.err"

echo "image-tar-fixture ok"
