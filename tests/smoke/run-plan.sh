#!/usr/bin/env bash
set -euo pipefail

tags=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag)
      if [ "$#" -lt 2 ]; then
        echo "--tag requires a value" >&2
        exit 1
      fi
      tags+=("$2")
      shift 2
      ;;
    --help|-h)
      echo "usage: tests/smoke/run-plan.sh [--tag tag ...] <image-ref> <smoke-plan.json>" >&2
      echo "   or: tests/smoke/run-plan.sh [--tag tag ...] <image-name>" >&2
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

target="${1:-}"
plan_file="${2:-}"
smoke_log_dir="${SMOKE_LOG_DIR:-smoke-logs}"

if [ -z "$target" ]; then
  echo "usage: tests/smoke/run-plan.sh [--tag tag ...] <image-ref> <smoke-plan.json>" >&2
  echo "   or: tests/smoke/run-plan.sh [--tag tag ...] <image-name>" >&2
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

mkdir -p "$smoke_log_dir"

jq_filter='.tests[]'
if [ "${#tags[@]}" -gt 0 ]; then
  jq_filter='.tests[] | select([.tags[]] as $caseTags | ($requiredTags | all(. as $tag | $caseTags | index($tag))))'
fi

jq -c --argjson requiredTags "$(printf '%s\n' "${tags[@]}" | jq -R . | jq -s .)" "$jq_filter" "$plan_file" |
while IFS= read -r test; do
  id="$(printf '%s' "$test" | jq -r '.id')"
  timeout_seconds="$(printf '%s' "$test" | jq -r '.timeoutSeconds // 30')"
  mapfile -t command_parts < <(printf '%s' "$test" | jq -r '.command[]')
  mapfile -t requires < <(printf '%s' "$test" | jq -r '.requires[]?')
  log_file="$smoke_log_dir/${id//\//_}.log"

  if [ "${#command_parts[@]}" -eq 0 ]; then
    echo "skip $id"
    printf 'skip %s\nreason=empty command\n' "$id" >"$log_file"
    continue
  fi

  for requirement in "${requires[@]}"; do
    {
      printf 'fail %s\n' "$id"
      printf 'unsupported requirement=%s\n' "$requirement"
    } | tee "$log_file" >&2
    exit 1
  done

  echo "==> $id"
  {
    printf 'image=%s\n' "$image_ref"
    printf 'id=%s\n' "$id"
    printf 'tags=%s\n' "$(printf '%s' "$test" | jq -c '.tags')"
    printf 'requires=%s\n' "$(printf '%s' "$test" | jq -c '.requires')"
    printf 'timeoutSeconds=%s\n' "$timeout_seconds"
    printf 'command='
    printf '%q ' "${command_parts[@]}"
    printf '\n'
    timeout "$timeout_seconds" docker run --rm --entrypoint "${command_parts[0]}" "$image_ref" "${command_parts[@]:1}"
  } 2>&1 | tee "$log_file"
done
