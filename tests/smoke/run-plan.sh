#!/usr/bin/env bash
set -euo pipefail

target="${1:-}"
plan_file="${2:-}"
smoke_log_dir="${SMOKE_LOG_DIR:-smoke-logs}"
require_docker_daemon="${SMOKE_REQUIRE_DOCKER_DAEMON:-0}"

if [ -z "$target" ]; then
  echo "usage: tests/smoke/run-plan.sh <image-ref> <smoke-plan.json>" >&2
  echo "   or: tests/smoke/run-plan.sh <image-name>" >&2
  exit 1
fi

if [ -z "$plan_file" ]; then
  image_name="$target"
  ci_plan="$(nix build ".#images.${image_name}.ci-plan-json" --print-out-paths --no-link)"
  image_ref="$(jq -r '.imageRef' "$ci_plan")"
  plan_file="$(nix build ".#images.${image_name}.smoke" --print-out-paths --no-link)"
else
  image_ref="$target"
fi

if [ ! -f "$plan_file" ]; then
  echo "smoke plan not found: $plan_file" >&2
  exit 1
fi

docker_info_ok=0
tcp_docker_ok=0
docker_env_args=()

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker_info_ok=1
fi

case "${DOCKER_HOST:-}" in
  tcp://*)
    if [ "$docker_info_ok" -eq 1 ]; then
      tcp_docker_ok=1
      docker_env_args+=(--env "DOCKER_HOST=${DOCKER_HOST}")
      if [ -n "${DOCKER_TLS_VERIFY:-}" ]; then
        docker_env_args+=(--env "DOCKER_TLS_VERIFY=${DOCKER_TLS_VERIFY}")
      fi
      if [ -n "${DOCKER_CERT_PATH:-}" ]; then
        docker_env_args+=(--env "DOCKER_CERT_PATH=${DOCKER_CERT_PATH}")
        if [ -d "${DOCKER_CERT_PATH}" ]; then
          docker_env_args+=(-v "${DOCKER_CERT_PATH}:${DOCKER_CERT_PATH}:ro")
        fi
      fi
    fi
    ;;
esac

mkdir -p "$smoke_log_dir"

jq -c '.tests[]' "$plan_file" | while IFS= read -r test; do
  name="$(printf '%s' "$test" | jq -r '.name')"
  mapfile -t command_parts < <(printf '%s' "$test" | jq -r '.command[]')
  log_file="$smoke_log_dir/${name}.log"

  if [ "${#command_parts[@]}" -eq 0 ]; then
    echo "skip $name"
    printf 'skip %s\n' "$name" >"$log_file"
    continue
  fi

  if [ "$name" = "docker-remote-version" ] && [ "$tcp_docker_ok" -ne 1 ]; then
    if [ "$require_docker_daemon" = "1" ]; then
      {
        printf 'fail %s\n' "$name"
        printf 'DOCKER_HOST must be a reachable tcp:// endpoint for release smoke\n'
      } | tee "$log_file" >&2
      exit 1
    fi
    echo "skip $name"
    {
      printf 'skip %s\n' "$name"
      printf 'host_docker_info=%s\n' "$docker_info_ok"
      printf 'DOCKER_HOST=%s\n' "${DOCKER_HOST:-}"
      printf 'reason=no reachable tcp Docker daemon was provided\n'
    } >"$log_file"
    continue
  fi

  echo "==> $name"
  {
    printf 'image=%s\n' "$image_ref"
    printf 'command='
    printf '%q ' "${command_parts[@]}"
    printf '\n'
    if [ "$name" = "docker-remote-version" ]; then
      docker run --rm "${docker_env_args[@]}" --entrypoint "${command_parts[0]}" "$image_ref" "${command_parts[@]:1}"
    else
      docker run --rm --entrypoint "${command_parts[0]}" "$image_ref" "${command_parts[@]:1}"
    fi
  } 2>&1 | tee "$log_file"
done
