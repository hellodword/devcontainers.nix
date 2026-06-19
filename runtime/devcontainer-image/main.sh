set -euo pipefail

usage() {
  cat <<'EOF'
devcontainer-image explain layer <n> [--report <dir>]
devcontainer-image explain package <name> [--report <dir>]
devcontainer-image explain extension <id> [--report <dir>]
devcontainer-image explain env <name> [--report <dir>]
devcontainer-image explain filesystem [--report <dir>]
devcontainer-image explain image-plan [--report <dir>]
devcontainer-image explain security [--report <dir>]
devcontainer-image diff <old-layer-plan.json> <new-layer-plan.json>
devcontainer-image check <metadata-label.json>
devcontainer-image doctor image <name>
EOF
}

require_file() {
  local path="$1"
  [ -f "$path" ] || {
    echo "missing report file: $path" >&2
    exit 1
  }
}

report_dir="."
if [ "${*: -2:1}" = "--report" ]; then
  report_dir="${*: -1}"
  set -- "${@:1:$(($#-2))}"
fi

cmd="${1:-}"
case "$cmd" in
  explain)
    topic="${2:-}"
    target="${3:-}"
    case "$topic" in
      layer)
        require_file "$report_dir/layer-plan.json"
        jq -e --argjson idx "${target:-0}" '.layers[$idx]' "$report_dir/layer-plan.json" >/dev/null || {
          echo "layer index not found: ${target:-0}" >&2
          exit 1
        }
        jq --argjson idx "${target:-0}" '.layers[$idx]' "$report_dir/layer-plan.json"
        ;;
      package)
        require_file "$report_dir/closure-report.json"
        jq -e --arg target "$target" '.packages[] | select(. == $target)' "$report_dir/closure-report.json" >/dev/null || {
          echo "package not found: $target" >&2
          exit 1
        }
        jq --arg target "$target" '.packages[] | select(. == $target)' "$report_dir/closure-report.json"
        ;;
      extension)
        require_file "$report_dir/extensions-index.json"
        jq -e --arg target "$target" '.extensions[] | select(.id == $target)' "$report_dir/extensions-index.json" >/dev/null || {
          echo "extension not found: $target" >&2
          exit 1
        }
        jq --arg target "$target" '.extensions[] | select(.id == $target)' "$report_dir/extensions-index.json"
        ;;
      env)
        require_file "$report_dir/env-report.json"
        jq -e --arg target "$target" '
          if $target == "PATH" then
            .containerEnvSources.PATH
          else
            .containerEnvSources[$target]
            // .remoteEnvSources[$target]
            // .shellEnvSources[$target]
          end
        ' "$report_dir/env-report.json" >/dev/null || {
          echo "environment entry not found: $target" >&2
          exit 1
        }
        jq --arg target "$target" '
          if $target == "PATH" then
            .containerEnvSources.PATH
          else
            .containerEnvSources[$target]
            // .remoteEnvSources[$target]
            // .shellEnvSources[$target]
          end
        ' "$report_dir/env-report.json"
        ;;
      filesystem)
        require_file "$report_dir/filesystem-report.json"
        cat "$report_dir/filesystem-report.json"
        ;;
      image-plan)
        require_file "$report_dir/image-plan.json"
        cat "$report_dir/image-plan.json"
        ;;
      security)
        require_file "$report_dir/security-report.json"
        cat "$report_dir/security-report.json"
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
    ;;
  diff)
    old_file="${2:-}"
    new_file="${3:-}"
    if [ -z "$old_file" ] || [ -z "$new_file" ]; then
      usage >&2
      exit 1
    fi
    old_lines="$(mktemp)"
    new_lines="$(mktemp)"
    added_jsonl="$(mktemp)"
    removed_jsonl="$(mktemp)"
    changed_jsonl="$(mktemp)"

    jq -c '.layers[] | {group, members, priority, estimatedCompressedSizeMiB}' "$old_file" >"$old_lines"
    jq -c '.layers[] | {group, members, priority, estimatedCompressedSizeMiB}' "$new_file" >"$new_lines"

    while IFS= read -r group; do
      before_json="$(jq -c --arg group "$group" 'select(.group == $group)' "$old_lines")"
      after_json="$(jq -c --arg group "$group" 'select(.group == $group)' "$new_lines")"

      if [ -z "$before_json" ]; then
        jq -nc --argjson after "$after_json" '{group: $after.group, after: $after, reasons: ["new layer"]}' >>"$added_jsonl"
        continue
      fi

      if [ -z "$after_json" ]; then
        jq -nc --argjson before "$before_json" '{group: $before.group, before: $before, reasons: ["removed layer"]}' >>"$removed_jsonl"
        continue
      fi

      reasons=()
      before_members="$(jq -c '.members' <<<"$before_json")"
      after_members="$(jq -c '.members' <<<"$after_json")"
      before_priority="$(jq -r '.priority' <<<"$before_json")"
      after_priority="$(jq -r '.priority' <<<"$after_json")"
      before_size="$(jq -r '.estimatedCompressedSizeMiB' <<<"$before_json")"
      after_size="$(jq -r '.estimatedCompressedSizeMiB' <<<"$after_json")"

      if [ "$before_members" != "$after_members" ]; then
        reasons+=("members changed")
      fi
      if [ "$before_priority" != "$after_priority" ]; then
        reasons+=("priority changed")
      fi
      if [ "$before_size" != "$after_size" ]; then
        reasons+=("estimatedCompressedSizeMiB changed")
      fi

      if [ "${#reasons[@]}" -gt 0 ]; then
        reasons_json="$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)"
        jq -nc \
          --argjson before "$before_json" \
          --argjson after "$after_json" \
          --argjson reasons "$reasons_json" \
          '{group: $after.group, before: $before, after: $after, reasons: $reasons}' >>"$changed_jsonl"
      fi
    done < <(
      {
        jq -r '.group' "$old_lines"
        jq -r '.group' "$new_lines"
      } | sort -u
    )

    jq -n \
      --slurpfile added "$added_jsonl" \
      --slurpfile removed "$removed_jsonl" \
      --slurpfile changed "$changed_jsonl" \
      '{
        added: $added,
        removed: $removed,
        changed: $changed
      }'

    rm -f "$old_lines" "$new_lines" "$added_jsonl" "$removed_jsonl" "$changed_jsonl"
    ;;
  check)
    metadata_file="${2:-}"
    [ -n "$metadata_file" ] || { usage >&2; exit 1; }
    require_file "$metadata_file"
    jq -e 'type == "array" and length > 0' "$metadata_file" >/dev/null
    ;;
  doctor)
    scope="${2:-}"
    target="${3:-}"
    if [ "$scope" = "image" ]; then
      if command -v docker >/dev/null 2>&1; then
        docker inspect "$target"
      else
        echo "docker unavailable in current environment; inspect $target elsewhere"
      fi
    else
      usage >&2
      exit 1
    fi
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
