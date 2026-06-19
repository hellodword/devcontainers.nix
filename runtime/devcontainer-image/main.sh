set -euo pipefail

usage() {
  cat <<'EOF'
devcontainer-image explain layer <n> [--report <dir>]
devcontainer-image explain package <name> [--report <dir>]
devcontainer-image explain extension <id> [--report <dir>]
devcontainer-image explain docker-access [--report <dir>]
devcontainer-image diff <old-layer-plan.json> <new-layer-plan.json>
devcontainer-image check <metadata-label.json>
devcontainer-image doctor image <name>
EOF
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
        jq --argjson idx "${target:-0}" '.layers[$idx]' "$report_dir/layer-plan.json"
        ;;
      package)
        jq --arg target "$target" '.packages[] | select(. == $target)' "$report_dir/closure-report.json"
        ;;
      extension)
        jq --arg target "$target" '.extensions[] | select(.id == $target)' "$report_dir/extensions-index.json"
        ;;
      docker-access)
        cat "$report_dir/docker-access-report.json"
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
    diff -u <(jq -S . "$old_file") <(jq -S . "$new_file") || true
    ;;
  check)
    metadata_file="${2:-}"
    [ -n "$metadata_file" ] || { usage >&2; exit 1; }
    jq -e 'type == "array"' "$metadata_file" >/dev/null
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
