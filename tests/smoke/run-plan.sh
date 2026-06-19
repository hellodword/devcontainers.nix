#!/usr/bin/env bash
set -euo pipefail

image_ref="${1:-}"
plan_file="${2:-}"
extra_args="${DOCKER_RUN_EXTRA_ARGS:-}"

if [ -z "$image_ref" ] || [ -z "$plan_file" ]; then
  echo "usage: tests/smoke/run-plan.sh <image-ref> <smoke-plan.json>" >&2
  exit 1
fi

if [ ! -f "$plan_file" ]; then
  echo "smoke plan not found: $plan_file" >&2
  exit 1
fi

split_extra_args() {
  if [ -n "$extra_args" ]; then
    read -r -a docker_extra <<<"$extra_args"
  else
    docker_extra=()
  fi
}

split_extra_args

jq -c '.tests[]' "$plan_file" | while IFS= read -r test; do
  name="$(printf '%s' "$test" | jq -r '.name')"
  mapfile -t command_parts < <(printf '%s' "$test" | jq -r '.command[]')

  if [ "${#command_parts[@]}" -eq 0 ]; then
    echo "skip $name"
    continue
  fi

  echo "==> $name"
  docker run --rm "${docker_extra[@]}" --entrypoint "${command_parts[0]}" "$image_ref" "${command_parts[@]:1}"
done
