set -euo pipefail

nixpkgs_ref="${DEVPKG_NIXPKGS_REF:-nixpkgs}"
current_system_value=""

usage() {
  cat <<'EOF'
devpkg add <package>...
devpkg remove <package>...
devpkg list [--json]
devpkg search <query>
devpkg add-lib [--outputs <outputs>] <package>...
devpkg add-lib --raw <installable>...
devpkg remove-lib <package>...
devpkg list-lib [--json]
devpkg add-dev-lib [--outputs <outputs>] <package>...
devpkg add-dev-lib --raw <installable>...
devpkg remove-dev-lib <package>...
devpkg list-dev-lib [--json]
devpkg help

examples:
  devpkg add cowsay
  devpkg remove cowsay
  devpkg list
  devpkg add-lib zlib
  devpkg add-dev-lib openssl
  devpkg add-dev-lib --outputs out,dev,static zlib
  devpkg add-dev-lib --raw 'nixpkgs#openssl^out,dev'
EOF
}

die() {
  printf 'devpkg: %s\n' "$*" >&2
  exit 1
}

nixpkgs_defaults() {
  export NIXPKGS_CONFIG="${NIXPKGS_CONFIG:-/etc/nixpkgs/config.nix}"
  export NIXPKGS_ALLOW_UNFREE="${NIXPKGS_ALLOW_UNFREE:-1}"
  export NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM="${NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM:-1}"
  export NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE="${NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE:-1}"
}

nix_eval() {
  nixpkgs_defaults
  nix eval --impure "$@"
}

nix_profile_add() {
  nixpkgs_defaults
  nix profile add --impure "$@"
}

nix_search() {
  nixpkgs_defaults
  nix search --impure "$@"
}

current_system() {
  if [ -z "$current_system_value" ]; then
    current_system_value="$(nix_eval --expr builtins.currentSystem --raw)"
  fi
  printf '%s\n' "$current_system_value"
}

default_xdg_data_home() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s\n' "$XDG_DATA_HOME"
  elif [ -n "${HOME:-}" ]; then
    printf '%s/.local/share\n' "$HOME"
  else
    die "HOME or XDG_DATA_HOME is required"
  fi
}

runtime_library_profile() {
  if [ -n "${DEVPKG_RUNTIME_LIBRARY_PROFILE:-}" ]; then
    printf '%s\n' "$DEVPKG_RUNTIME_LIBRARY_PROFILE"
  else
    printf '%s/devpkg/runtime-libraries/profile\n' "$(default_xdg_data_home)"
  fi
}

build_library_profile() {
  if [ -n "${DEVPKG_BUILD_LIBRARY_PROFILE:-}" ]; then
    printf '%s\n' "$DEVPKG_BUILD_LIBRARY_PROFILE"
  else
    printf '%s/devpkg/build-libraries/profile\n' "$(default_xdg_data_home)"
  fi
}

ensure_profile_parent() {
  local profile="$1"
  mkdir -p "$(dirname "$profile")"
}

normalize_attr() {
  local spec="${1:-}"
  local system

  [ -n "$spec" ] || die "package name is required"

  spec="${spec%%^*}"
  case "$spec" in
    *#*) spec="${spec##*#}" ;;
  esac
  spec="${spec#pkgs.}"

  system="$(current_system)"
  spec="${spec#legacyPackages."${system}".}"
  spec="${spec#packages."${system}".}"

  printf '%s\n' "$spec"
}

installable_for() {
  local attr
  attr="$(normalize_attr "$1")"
  printf '%s#%s\n' "$nixpkgs_ref" "$attr"
}

installable_for_outputs() {
  local attr="$1"
  local outputs="$2"
  printf '%s#%s^%s\n' "$nixpkgs_ref" "$attr" "$outputs"
}

nix_string_literal() {
  jq -nr --arg value "$1" '$value | @json'
}

profile_json() {
  nix profile list --json --no-pretty
}

profile_json_for() {
  local profile="$1"

  if nix profile list --profile "$profile" --json --no-pretty 2>/dev/null; then
    return 0
  fi

  printf '{"elements":{}}\n'
}

package_outputs() {
  local attr="$1"
  local system

  system="$(current_system)"
  if nix_eval --json "$nixpkgs_ref#legacyPackages.${system}.${attr}.outputs" 2>/dev/null; then
    return 0
  fi

  if nix_eval --json "$nixpkgs_ref#packages.${system}.${attr}.outputs" 2>/dev/null; then
    return 0
  fi

  printf '["out"]\n'
}

runtime_output_from_json() {
  jq -r '
    if index("lib") then
      "lib"
    elif index("out") then
      "out"
    else
      .[0]
    end
  '
}

default_outputs_for() {
  local mode="$1"
  local attr="$2"
  local outputs_json runtime_output

  outputs_json="$(package_outputs "$attr")"
  runtime_output="$(printf '%s\n' "$outputs_json" | runtime_output_from_json)"

  if [ "$mode" = "runtime" ]; then
    printf '%s\n' "$runtime_output"
  else
    printf '%s\n' "$outputs_json" | jq -r --arg runtime "$runtime_output" '
      [$runtime] + (if index("dev") and $runtime != "dev" then ["dev"] else [] end)
      | join(",")
    '
  fi
}

normalize_outputs_arg() {
  local outputs="$1"
  outputs="${outputs// /,}"
  outputs="${outputs#,}"
  outputs="${outputs%,}"
  [ -n "$outputs" ] || die "--outputs requires at least one output"
  printf '%s\n' "$outputs"
}

resolve_profile_name_from_json() {
  local requested="$1"
  local json_command="$2"
  local attr base
  local -a matches

  attr="$(normalize_attr "$requested")"
  base="${attr##*.}"

  mapfile -t matches < <(
    "$json_command" | jq -r \
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

resolve_profile_name() {
  local requested="$1"
  resolve_profile_name_from_json "$requested" profile_json
}

make_profile_json_command() {
  local profile="$1"
  local function_name="$2"
  eval "$function_name() { profile_json_for \"\$profile\"; }"
}

cmd_add_packages() {
  local -a installables

  installables=()
  [ "$#" -gt 0 ] || { usage >&2; exit 1; }
  for package in "$@"; do
    installables+=("$(installable_for "$package")")
  done
  nix_profile_add "${installables[@]}"
}

cmd_remove_packages() {
  local -a removals

  removals=()
  [ "$#" -gt 0 ] || { usage >&2; exit 1; }
  for package in "$@"; do
    removals+=("$(resolve_profile_name "$package")")
  done
  nix profile remove "${removals[@]}"
}

cmd_list_packages() {
  if [ "${1:-}" = "--json" ]; then
    profile_json
  elif [ "$#" -eq 0 ]; then
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
}

cmd_add_libraries() {
  local mode="$1"
  local profile="$2"
  local raw=false
  local outputs=""
  local -a specs installables
  local spec attr selected_outputs

  shift 2
  specs=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --raw)
        raw=true
        shift
        ;;
      --outputs)
        [ "$#" -ge 2 ] || die "--outputs requires a value"
        outputs="$(normalize_outputs_arg "$2")"
        shift 2
        ;;
      --outputs=*)
        outputs="$(normalize_outputs_arg "${1#--outputs=}")"
        shift
        ;;
      --)
        shift
        specs+=("$@")
        break
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        specs+=("$1")
        shift
        ;;
    esac
  done

  [ "${#specs[@]}" -gt 0 ] || { usage >&2; exit 1; }
  if [ "$raw" = true ] && [ -n "$outputs" ]; then
    die "--raw cannot be combined with --outputs"
  fi

  installables=()
  for spec in "${specs[@]}"; do
    if [ "$raw" = true ]; then
      installables+=("$spec")
    else
      attr="$(normalize_attr "$spec")"
      if [ -n "$outputs" ]; then
        selected_outputs="$outputs"
      else
        selected_outputs="$(default_outputs_for "$mode" "$attr")"
      fi
      installables+=("$(installable_for_outputs "$attr" "$selected_outputs")")
    fi
  done

  ensure_profile_parent "$profile"
  nix_profile_add --profile "$profile" "${installables[@]}"
}

cmd_remove_libraries() {
  local profile="$1"
  local -a removals
  local profile_json_command="profile_json_selected"

  shift
  [ "$#" -gt 0 ] || { usage >&2; exit 1; }

  make_profile_json_command "$profile" "$profile_json_command"
  removals=()
  for package in "$@"; do
    removals+=("$(resolve_profile_name_from_json "$package" "$profile_json_command")")
  done
  nix profile remove --profile "$profile" "${removals[@]}"
}

cmd_list_libraries() {
  local profile="$1"

  shift
  if [ "${1:-}" = "--json" ]; then
    profile_json_for "$profile"
  elif [ "$#" -eq 0 ]; then
    profile_json_for "$profile" | jq -r '
      .elements
      | to_entries
      | sort_by(.key)
      | .[]
      | "\(.key)\t\(.value.attrPath // "")\t\((.value.outputs // []) | join(","))"
    '
  else
    usage >&2
    exit 1
  fi
}

complete_commands() {
  local prefix="${1:-}"
  local command
  local -a commands=(
    add
    install
    remove
    rm
    uninstall
    list
    ls
    search
    add-lib
    remove-lib
    list-lib
    add-dev-lib
    remove-dev-lib
    list-dev-lib
    help
    -h
    --help
  )

  for command in "${commands[@]}"; do
    case "$command" in
      "$prefix"*) printf '%s\n' "$command" ;;
    esac
  done
}

complete_outputs() {
  local prefix="${1:-}"
  local output
  local -a outputs=(
    out
    dev
    lib
    static
    doc
    man
    debug
  )

  for output in "${outputs[@]}"; do
    case "$output" in
      "$prefix"*) printf '%s\n' "$output" ;;
    esac
  done
}

complete_packages() {
  local prefix="${1:-}"
  local parent="" leaf="$prefix"
  local ref_literal parent_literal leaf_literal

  case "$prefix" in
    *.*)
      parent="${prefix%.*}"
      leaf="${prefix##*.}"
      ;;
  esac

  ref_literal="$(nix_string_literal "$nixpkgs_ref")"
  parent_literal="$(nix_string_literal "$parent")"
  leaf_literal="$(nix_string_literal "$leaf")"

  nix_eval --json --expr "
    let
      ref = ${ref_literal};
      parent = ${parent_literal};
      leaf = ${leaf_literal};
      flake = builtins.getFlake ref;
      system = builtins.currentSystem;
      pkgs =
        if flake ? legacyPackages && builtins.hasAttr system flake.legacyPackages then
          flake.legacyPackages.\${system}
        else
          flake.packages.\${system};
      parts = builtins.filter (part: builtins.isString part && part != \"\") (builtins.split \"\\\\.\" parent);
      scope = builtins.foldl'
        (current: name:
          if builtins.isAttrs current && builtins.hasAttr name current then
            builtins.getAttr name current
          else
            { })
        pkgs
        parts;
      matches = builtins.filter
        (name: builtins.substring 0 (builtins.stringLength leaf) name == leaf)
        (if builtins.isAttrs scope then builtins.attrNames scope else [ ]);
    in
      map (name: if parent == \"\" then name else parent + \".\" + name) matches
  " 2>/dev/null | jq -r '.[]' 2>/dev/null || true
}

complete_installed() {
  local mode="${1:-}"
  local prefix="${2:-}"

  case "$mode" in
    main)
      profile_json
      ;;
    runtime)
      profile_json_for "$(runtime_library_profile)"
      ;;
    build)
      profile_json_for "$(build_library_profile)"
      ;;
    *)
      die "unknown completion profile: $mode"
      ;;
  esac | jq -r --arg prefix "$prefix" '
    .elements
    | keys[]
    | select(startswith($prefix))
  ' 2>/dev/null || true
}

cmd_complete() {
  local subject="${1:-}"
  shift || true

  case "$subject" in
    commands)
      complete_commands "${1:-}"
      ;;
    packages)
      complete_packages "${1:-}"
      ;;
    installed)
      complete_installed "${1:-}" "${2:-}"
      ;;
    outputs)
      complete_outputs "${1:-}"
      ;;
    *)
      die "unknown completion subject: $subject"
      ;;
  esac
}

cmd="${1:-}"
case "$cmd" in
  add | install)
    shift
    cmd_add_packages "$@"
    ;;
  remove | rm | uninstall)
    shift
    cmd_remove_packages "$@"
    ;;
  list | ls)
    shift
    cmd_list_packages "$@"
    ;;
  search)
    query="${2:-}"
    [ -n "$query" ] || { usage >&2; exit 1; }
    nix_search "$nixpkgs_ref" "$query"
    ;;
  add-lib)
    shift
    cmd_add_libraries runtime "$(runtime_library_profile)" "$@"
    ;;
  remove-lib)
    shift
    cmd_remove_libraries "$(runtime_library_profile)" "$@"
    ;;
  list-lib)
    shift
    cmd_list_libraries "$(runtime_library_profile)" "$@"
    ;;
  add-dev-lib)
    shift
    cmd_add_libraries build "$(build_library_profile)" "$@"
    ;;
  remove-dev-lib)
    shift
    cmd_remove_libraries "$(build_library_profile)" "$@"
    ;;
  list-dev-lib)
    shift
    cmd_list_libraries "$(build_library_profile)" "$@"
    ;;
  complete)
    shift
    cmd_complete "$@"
    ;;
  help | -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
