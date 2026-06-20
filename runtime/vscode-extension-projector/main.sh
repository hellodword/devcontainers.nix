set -euo pipefail

usage() {
  cat <<'EOF'
vscode-extension-projector activate --index <path>
EOF
}

redact_log_line() {
  printf '%s\n' "$1" | sed -E 's/([A-Za-z0-9_]*(TOKEN|PASSWORD|SECRET|KEY)[A-Za-z0-9_]*=)[^[:space:]]+/\1[REDACTED]/g'
}

copy_or_link() {
  local source_path="$1"
  local target_path="$2"
  local projection="$3"

  rm -rf "$target_path"
  mkdir -p "$(dirname "$target_path")"

  case "$projection" in
    copy|copy-if-needed|copy-if-needed-with-fhs)
      cp -a "$source_path" "$target_path"
      ;;
    *)
      ln -sfn "$source_path" "$target_path"
      ;;
  esac
}

cmd="${1:-}"
case "$cmd" in
  activate)
    shift
    [ "${1:-}" = "--index" ] || { usage >&2; exit 1; }
    index_file="${2:-}"
    [ -n "$index_file" ] || { usage >&2; exit 1; }
    [ -f "$index_file" ] || { echo "index file not found: $index_file" >&2; exit 1; }

    mapfile -t targets < <(jq -r '.projectionTargets[]' "$index_file")
    jq -c '.extensions[]' "$index_file" | while IFS= read -r extension; do
      id="$(printf '%s' "$extension" | jq -r '.id')"
      source_path="$(printf '%s' "$extension" | jq -r '.path')"
      projection="$(printf '%s' "$extension" | jq -r '.projection')"
      dest_name="$(basename "$source_path")"

      if [ ! -e "$source_path" ]; then
        redact_log_line "missing extension source for $id: $source_path" >&2
        continue
      fi

      for target in "${targets[@]}"; do
        redact_log_line "project $id -> $target/$dest_name"
        copy_or_link "$source_path" "$target/$dest_name" "$projection"
      done
    done
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
