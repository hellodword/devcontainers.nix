set -euo pipefail

usage() {
  cat <<'EOF'
devcontainer-image explain layer <n> [--report <dir>]
devcontainer-image explain package <name> [--report <dir>]
devcontainer-image explain extension <id> [--report <dir>]
devcontainer-image explain docker-access [--report <dir>]
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
      docker-access)
        require_file "$report_dir/docker-access-report.json"
        cat "$report_dir/docker-access-report.json"
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
    old_tmp="$(mktemp)"
    new_tmp="$(mktemp)"
    jq -S '.layers | map({group, members, priority, estimatedCompressedSizeMiB})' "$old_file" >"$old_tmp"
    jq -S '.layers | map({group, members, priority, estimatedCompressedSizeMiB})' "$new_file" >"$new_tmp"
    diff -u "$old_tmp" "$new_tmp" || true
    rm -f "$old_tmp" "$new_tmp"
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
