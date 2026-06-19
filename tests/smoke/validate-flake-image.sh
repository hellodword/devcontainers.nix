#!/usr/bin/env bash
set -euo pipefail

image_name="${1:-}"
extra_args="${DOCKER_RUN_EXTRA_ARGS:-}"

if [ -z "$image_name" ]; then
  echo "usage: tests/smoke/validate-flake-image.sh <image-name>" >&2
  echo "example: tests/smoke/validate-flake-image.sh nix-dind" >&2
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

oci_path="$(nix build ".#images.${image_name}.oci" --print-out-paths --no-link)"
plan_path="$(nix build ".#images.${image_name}.smoke" --print-out-paths --no-link)"

gzip -dc "$oci_path" | docker load

if [ -n "$extra_args" ]; then
  export DOCKER_RUN_EXTRA_ARGS="$extra_args"
fi

export SMOKE_LOG_DIR="${SMOKE_LOG_DIR:-smoke-logs-${image_name}}"

chmod +x tests/smoke/run-plan.sh
./tests/smoke/run-plan.sh "devcontainer-${image_name}:latest" "$plan_path"
