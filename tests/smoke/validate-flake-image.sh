#!/usr/bin/env bash
set -euo pipefail

image_name="${1:-}"

if [ -z "$image_name" ]; then
  echo "usage: tests/smoke/validate-flake-image.sh <image-name>" >&2
  echo "example: tests/smoke/validate-flake-image.sh nix-latest" >&2
  exit 1
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "nix is required" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required" >&2
  exit 1
fi

nix run ".#load-${image_name}"

export SMOKE_LOG_DIR="${SMOKE_LOG_DIR:-smoke-logs-${image_name}}"

chmod +x tests/smoke/run-plan.sh
./tests/smoke/run-plan.sh "$image_name"
