set -euo pipefail

nixpkgs_ref="${DEVPKG_NIXPKGS_REF:-nixpkgs}"

usage() {
  cat <<'EOF'
devpkg add <package>...
devpkg remove <package>...
devpkg list [--json]
devpkg search <query>
devpkg help

examples:
  devpkg add cowsay
  devpkg remove cowsay
  devpkg list
EOF
}

die() {
  printf 'devpkg: %s\n' "$*" >&2
  exit 1
}

normalize_attr() {
  local spec="${1:-}"

  [ -n "$spec" ] || die "package name is required"

  spec="${spec#nixpkgs#}"
  spec="${spec#pkgs.}"

  printf '%s\n' "$spec"
}

installable_for() {
  local attr
  attr="$(normalize_attr "$1")"
  printf '%s#%s\n' "$nixpkgs_ref" "$attr"
}

profile_json() {
  nix profile list --json --no-pretty
}

resolve_profile_name() {
  local requested attr base
  local -a matches

  requested="$1"
  attr="$(normalize_attr "$requested")"
  base="${attr##*.}"

  mapfile -t matches < <(
    profile_json | jq -r \
      --arg requested "$requested" \
      --arg attr "$attr" \
      --arg base "$base" \
      '
        .elements
        | to_entries
        | map(
            select(
              .key == $requested
              or .key == $attr
              or .key == $base
              or ((.value.attrPath // "") == $attr)
              or ((.value.attrPath // "") | endswith("." + $attr))
              or ((.value.attrPath // "") | endswith("." + $base))
            )
          )
        | map(.key)
        | unique
        | .[]
      '
  )

  case "${#matches[@]}" in
    0)
      die "package not installed: $requested"
      ;;
    1)
      printf '%s\n' "${matches[0]}"
      ;;
    *)
      printf 'devpkg: package name is ambiguous: %s\n' "$requested" >&2
      printf 'matches:\n' >&2
      printf '  %s\n' "${matches[@]}" >&2
      exit 1
      ;;
  esac
}

cmd="${1:-}"
case "$cmd" in
  add | install)
    local_installables=()
    shift
    [ "$#" -gt 0 ] || { usage >&2; exit 1; }
    for package in "$@"; do
      local_installables+=("$(installable_for "$package")")
    done
    nix profile add "${local_installables[@]}"
    ;;
  remove | rm | uninstall)
    local_removals=()
    shift
    [ "$#" -gt 0 ] || { usage >&2; exit 1; }
    for package in "$@"; do
      local_removals+=("$(resolve_profile_name "$package")")
    done
    nix profile remove "${local_removals[@]}"
    ;;
  list | ls)
    if [ "${2:-}" = "--json" ]; then
      profile_json
    elif [ "$#" -eq 1 ]; then
      profile_json | jq -r '
        .elements
        | to_entries
        | sort_by(.key)
        | .[]
        | "\(.key)\t\(.value.attrPath // "")"
      '
    else
      usage >&2
      exit 1
    fi
    ;;
  search)
    query="${2:-}"
    [ -n "$query" ] || { usage >&2; exit 1; }
    nix search "$nixpkgs_ref" "$query"
    ;;
  help | -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
