set -euo pipefail

user_packages_file="${XDG_CONFIG_HOME:-$HOME/.config}/devcontainer/devpkg/user-packages.nix"
history_file="${XDG_STATE_HOME:-$HOME/.local/state}/devcontainer/devpkg/history.json"
project_packages_file="${PWD}/.devcontainer/packages.nix"

usage() {
  cat <<'EOF'
devpkg run <attr> [-- args...]
devpkg add <attr>...
devpkg remove <attr>...
devpkg list
devpkg rollback [generation]
devpkg diff [generation-a] [generation-b]
devpkg search <query>
devpkg doctor
devpkg project init
devpkg freeze --scope user|project
EOF
}

ensure_user_state() {
  mkdir -p "$(dirname "$user_packages_file")" "$(dirname "$history_file")"
  [ -f "$history_file" ] || printf '[]\n' >"$history_file"
}

cmd="${1:-}"
case "$cmd" in
  run)
    attr="${2:-}"
    [ -n "$attr" ] || { usage >&2; exit 1; }
    shift 2
    if [ "${1:-}" = "--" ]; then
      shift
    fi
    nix shell "nixpkgs#$attr" --command "$attr" "$@"
    ;;
  add)
    ensure_user_state
    shift
    [ "$#" -gt 0 ] || { usage >&2; exit 1; }
    nix profile install "$@"
    ;;
  remove)
    shift
    [ "$#" -gt 0 ] || { usage >&2; exit 1; }
    nix profile remove "$@"
    ;;
  list)
    nix profile list
    ;;
  rollback)
    generation="${2:-}"
    if [ -n "$generation" ]; then
      nix profile rollback --to "$generation"
    else
      nix profile rollback
    fi
    ;;
  diff)
    a="${2:-}"
    b="${3:-}"
    nix profile history
    printf 'compare generations manually: %s %s\n' "${a:-current}" "${b:-target}"
    ;;
  search)
    query="${2:-}"
    [ -n "$query" ] || { usage >&2; exit 1; }
    nix search nixpkgs "$query"
    ;;
  doctor)
    command -v nix >/dev/null
    nix --version
    ;;
  project)
    sub="${2:-}"
    case "$sub" in
      init)
        mkdir -p .devcontainer
        if [ ! -f "$project_packages_file" ]; then
          cat >"$project_packages_file" <<'EOF'
{ pkgs }:
with pkgs; [
]
EOF
        fi
        ;;
      *)
        echo "project subcommand not implemented yet: $sub" >&2
        exit 1
        ;;
    esac
    ;;
  freeze)
    scope="${3:-}"
    case "$scope" in
      user)
        if [ -f "$user_packages_file" ]; then
          cat "$user_packages_file"
        else
          printf '{ pkgs }: with pkgs; [ ]\n'
        fi
        ;;
      project)
        if [ -f "$project_packages_file" ]; then
          cat "$project_packages_file"
        else
          printf '{ pkgs }: with pkgs; [ ]\n'
        fi
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
