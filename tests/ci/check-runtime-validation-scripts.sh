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

reports_dir="$tmpdir/reports"
mkdir -p "$reports_dir"
browser_root="$tmpdir/browser-root"
mkdir -p "$browser_root/run/wrappers/bin" "$browser_root/opt/devcontainer/browser-sandbox"
for helper in __chromium-suid-sandbox google-chrome-suid-sandbox microsoft-edge-suid-sandbox; do
  printf '#!/bin/sh\nexit 0\n' >"$browser_root/run/wrappers/bin/$helper"
  cp "$browser_root/run/wrappers/bin/$helper" "$browser_root/opt/devcontainer/browser-sandbox/$helper"
  chmod 0755 \
    "$browser_root/run/wrappers/bin/$helper" \
    "$browser_root/opt/devcontainer/browser-sandbox/$helper"
done

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

cat >"$reports_dir/browser-sandbox-report.json" <<'EOF'
{
  "enabled": true,
  "helperRoot": "/run/wrappers/bin",
  "runtimeHelperRoot": "/opt/devcontainer/browser-sandbox",
  "helpers": [
    {
      "browser": "chromium",
      "source": "/nix/store/fixture-chromium-sandbox/bin/__chromium-suid-sandbox",
      "targetPath": "/run/wrappers/bin/__chromium-suid-sandbox",
      "runtimePath": "/opt/devcontainer/browser-sandbox/__chromium-suid-sandbox",
      "package": "chromium",
      "mode": "4755",
      "owner": "root:root"
    },
    {
      "browser": "google-chrome",
      "source": "/nix/store/fixture-google-chrome/share/google/chrome/chrome-sandbox",
      "targetPath": "/run/wrappers/bin/google-chrome-suid-sandbox",
      "runtimePath": "/opt/devcontainer/browser-sandbox/google-chrome-suid-sandbox",
      "package": "google-chrome",
      "mode": "4755",
      "owner": "root:root"
    },
    {
      "browser": "microsoft-edge",
      "source": "/nix/store/fixture-microsoft-edge/share/microsoft/msedge/msedge-sandbox",
      "targetPath": "/run/wrappers/bin/microsoft-edge-suid-sandbox",
      "runtimePath": "/opt/devcontainer/browser-sandbox/microsoft-edge-suid-sandbox",
      "package": "microsoft-edge",
      "mode": "4755",
      "owner": "root:root"
    }
  ],
  "preinstalledBrowsers": [],
  "shims": []
}
EOF

cat >"$tmpdir/image.json" <<EOF
{
  "version": 1,
  "arch": "amd64",
  "image-config": {
    "User": "vscode",
    "WorkingDir": "/workspaces",
    "Env": [
      "HOME=/home/vscode",
      "XDG_CONFIG_HOME=/home/vscode/.config",
      "XDG_CACHE_HOME=/home/vscode/.cache",
      "XDG_DATA_HOME=/home/vscode/.local/share",
      "XDG_STATE_HOME=/home/vscode/.local/state",
      "LANG=en_US.UTF-8",
      "LANGUAGE=en_US:en",
      "LOCALE_ARCHIVE=/nix/store/fixture-glibc-locales/lib/locale/locale-archive",
      "XDG_CONFIG_DIRS=/etc/xdg",
      "XDG_DATA_DIRS=/usr/local/share:/usr/share:/share",
      "NIXPKGS_CONFIG=/etc/nixpkgs/config.nix",
      "NIXPKGS_ALLOW_UNFREE=1",
      "NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1",
      "NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1",
      "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
      "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
      "CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt",
      "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt"
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
      "paths": [
        {
          "path": "$browser_root",
          "options": {
            "rewrite": {
              "regex": "^$browser_root",
              "repl": ""
            },
            "perms": [
              {
                "regex": "^$browser_root/run/wrappers/bin/__chromium-suid-sandbox$",
                "mode": "4755",
                "uid": 0,
                "gid": 0,
                "uname": "root",
                "gname": "root"
              },
              {
                "regex": "^$browser_root/opt/devcontainer/browser-sandbox/__chromium-suid-sandbox$",
                "mode": "4755",
                "uid": 0,
                "gid": 0,
                "uname": "root",
                "gname": "root"
              },
              {
                "regex": "^$browser_root/run/wrappers/bin/google-chrome-suid-sandbox$",
                "mode": "4755",
                "uid": 0,
                "gid": 0,
                "uname": "root",
                "gname": "root"
              },
              {
                "regex": "^$browser_root/opt/devcontainer/browser-sandbox/google-chrome-suid-sandbox$",
                "mode": "4755",
                "uid": 0,
                "gid": 0,
                "uname": "root",
                "gname": "root"
              },
              {
                "regex": "^$browser_root/run/wrappers/bin/microsoft-edge-suid-sandbox$",
                "mode": "4755",
                "uid": 0,
                "gid": 0,
                "uname": "root",
                "gname": "root"
              },
              {
                "regex": "^$browser_root/opt/devcontainer/browser-sandbox/microsoft-edge-suid-sandbox$",
                "mode": "4755",
                "uid": 0,
                "gid": 0,
                "uname": "root",
                "gname": "root"
              }
            ]
          }
        }
      ],
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

echo "runtime-validation-scripts ok"
