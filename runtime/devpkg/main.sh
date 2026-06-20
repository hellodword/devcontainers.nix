set -euo pipefail

nixpkgs_ref="${DEVPKG_NIXPKGS_REF:-nixpkgs}"
current_system_value=""

usage() {
  cat <<'EOF'
devpkg add <package>...
devpkg remove <package>...
devpkg list [--json]
devpkg search <query>
devpkg browser-shims sync
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
  devpkg browser-shims sync
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

profile_json() {
  if [ -n "${DEVPKG_PROFILE_JSON_FILE:-}" ]; then
    cat "$DEVPKG_PROFILE_JSON_FILE"
    return 0
  fi

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

browser_shim_marker="devcontainers.nix browser sandbox shim"

browser_shim_dir() {
  printf '%s/devcontainer/bin\n' "$(default_xdg_data_home)"
}

# Keep these helper paths and generated shim behavior in sync with docs/browser-sandbox.md.
browser_helper_for() {
  case "$1" in
    chromium)
      printf '/opt/devcontainer/browser-sandbox/__chromium-suid-sandbox\n'
      ;;
    google-chrome)
      printf '/opt/devcontainer/browser-sandbox/google-chrome-suid-sandbox\n'
      ;;
    microsoft-edge)
      printf '/opt/devcontainer/browser-sandbox/microsoft-edge-suid-sandbox\n'
      ;;
    *)
      die "unsupported browser: $1"
      ;;
  esac
}

browser_commands_for() {
  case "$1" in
    chromium)
      printf 'chromium\nchromium-browser\n'
      ;;
    google-chrome)
      printf 'google-chrome\ngoogle-chrome-stable\n'
      ;;
    microsoft-edge)
      printf 'microsoft-edge\nmicrosoft-edge-stable\n'
      ;;
    *)
      die "unsupported browser: $1"
      ;;
  esac
}

filter_path_without_dir() {
  local remove="$1"
  local path_value="${2-${PATH:-}}"
  local old_ifs="$IFS"
  local entry
  local filtered=""

  IFS=:
  for entry in $path_value; do
    if [ -z "$entry" ] || [ "$entry" = "$remove" ]; then
      continue
    fi
    if [ -z "$filtered" ]; then
      filtered="$entry"
    else
      filtered="$filtered:$entry"
    fi
  done
  IFS="$old_ifs"

  printf '%s\n' "$filtered"
}

browser_real_command() {
  local command_name="$1"
  local filtered_path

  filtered_path="$(filter_path_without_dir "$(browser_shim_dir)" "${DEVPKG_BROWSER_COMMAND_PATH:-${PATH:-}}")"
  PATH="$filtered_path" command -v "$command_name" 2>/dev/null
}

browser_profile_installed() {
  local browser="$1"
  local profile="$2"

  printf '%s\n' "$profile" | jq -e --arg browser "$browser" '
    (.elements // {})
    | to_entries
    | any(
        .key == $browser
        or ((.value.attrPath // "") == $browser)
        or ((.value.attrPath // "") | endswith("." + $browser))
      )
  ' >/dev/null
}

browser_command_installed() {
  local browser="$1"
  local command_name

  while IFS= read -r command_name; do
    if [ -n "$command_name" ] && browser_real_command "$command_name" >/dev/null; then
      return 0
    fi
  done < <(browser_commands_for "$browser")

  return 1
}

browser_installed() {
  local browser="$1"
  local profile="$2"

  browser_profile_installed "$browser" "$profile" || browser_command_installed "$browser"
}

is_managed_browser_shim() {
  local path="$1"

  [ -f "$path" ] && grep -Fqx "# $browser_shim_marker" "$path"
}

write_browser_shim() {
  local browser="$1"
  local command_name="$2"
  local shim_dir="$3"
  local helper
  local target
  local tmp

  helper="$(browser_helper_for "$browser")"
  target="$shim_dir/$command_name"

  if [ -e "$target" ] && ! is_managed_browser_shim "$target"; then
    printf 'devpkg: preserving unmanaged browser shim: %s\n' "$target" >&2
    return 0
  fi

  mkdir -p "$shim_dir"
  tmp="$target.tmp.$$"
  cat >"$tmp" <<EOF
#!/usr/bin/env bash
# $browser_shim_marker
set -euo pipefail

browser_command='$command_name'
sandbox_helper='$helper'

filter_path_without_dir() {
  local remove="\$1"
  local old_ifs="\$IFS"
  local entry
  local filtered=""

  IFS=:
  for entry in \${PATH:-}; do
    if [ -z "\$entry" ] || [ "\$entry" = "\$remove" ]; then
      continue
    fi
    if [ -z "\$filtered" ]; then
      filtered="\$entry"
    else
      filtered="\$filtered:\$entry"
    fi
  done
  IFS="\$old_ifs"
  printf '%s\n' "\$filtered"
}

patch_chrome_devel_sandbox_exports() {
  local wrapper="\$1"
  local first_line
  local line
  local patch_dir
  local patched_wrapper
  local replaced=false

  if ! IFS= read -r first_line < "\$wrapper"; then
    return 1
  fi
  case "\$first_line" in
    "#!"*) ;;
    *) return 1 ;;
  esac

  if [ -n "\${XDG_RUNTIME_DIR:-}" ] && [ -d "\$XDG_RUNTIME_DIR" ] && [ -w "\$XDG_RUNTIME_DIR" ]; then
    patch_dir="\$XDG_RUNTIME_DIR/devcontainer-browser-shims"
  else
    patch_dir="\${TMPDIR:-/tmp}/devcontainer-browser-shims-\$UID"
  fi

  mkdir -p "\$patch_dir"
  patched_wrapper="\$patch_dir/\$browser_command"
  : > "\$patched_wrapper"

  while IFS= read -r line || [ -n "\$line" ]; do
    case "\$line" in
      *"export CHROME_DEVEL_SANDBOX="*)
        printf 'export CHROME_DEVEL_SANDBOX=%q\n' "\$sandbox_helper" >> "\$patched_wrapper"
        replaced=true
        ;;
      *)
        printf '%s\n' "\$line" >> "\$patched_wrapper"
        ;;
    esac
  done < "\$wrapper"

  if [ "\$replaced" = true ]; then
    chmod 0700 "\$patched_wrapper"
    printf '%s\n' "\$patched_wrapper"
    return 0
  fi

  return 1
}

shim_dir="\$(CDPATH= cd -- "\$(dirname -- "\${BASH_SOURCE[0]}")" && pwd -P)"
filtered_path="\$(filter_path_without_dir "\$shim_dir")"
if ! real_browser="\$(PATH="\$filtered_path" command -v "\$browser_command" 2>/dev/null)"; then
  printf 'devcontainers.nix: browser command not installed: %s\n' "\$browser_command" >&2
  exit 127
fi

if [ ! -x "\$sandbox_helper" ]; then
  printf 'devcontainers.nix: browser sandbox helper is not executable: %s\n' "\$sandbox_helper" >&2
  exit 126
fi

case "\$browser_command" in
  chromium | chromium-browser)
    if patched_browser="\$(patch_chrome_devel_sandbox_exports "\$real_browser")"; then
      export CHROME_DEVEL_SANDBOX="\$sandbox_helper"
      exec bash -e "\$patched_browser" "\$@"
    fi
    ;;
esac

export CHROME_DEVEL_SANDBOX="\$sandbox_helper"
exec "\$real_browser" "\$@"
EOF
  chmod 0755 "$tmp"
  mv "$tmp" "$target"
}

remove_browser_shim() {
  local command_name="$1"
  local shim_dir="$2"
  local target="$shim_dir/$command_name"

  if is_managed_browser_shim "$target"; then
    rm -f "$target"
  fi
}

sync_browser_shims_for() {
  local browser="$1"
  local installed="$2"
  local shim_dir="$3"
  local command_name

  while IFS= read -r command_name; do
    [ -n "$command_name" ] || continue
    if [ "$installed" = true ]; then
      write_browser_shim "$browser" "$command_name" "$shim_dir"
    else
      remove_browser_shim "$command_name" "$shim_dir"
    fi
  done < <(browser_commands_for "$browser")
}

cmd_browser_shims_sync() {
  local profile
  local shim_dir
  local browser

  [ "$#" -eq 0 ] || { usage >&2; exit 1; }

  profile="$(profile_json)"
  shim_dir="$(browser_shim_dir)"

  for browser in chromium google-chrome microsoft-edge; do
    if browser_installed "$browser" "$profile"; then
      sync_browser_shims_for "$browser" true "$shim_dir"
    else
      sync_browser_shims_for "$browser" false "$shim_dir"
    fi
  done
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

cmd="${1:-}"
case "$cmd" in
  add | install)
    shift
    cmd_add_packages "$@"
    cmd_browser_shims_sync
    ;;
  remove | rm | uninstall)
    shift
    cmd_remove_packages "$@"
    cmd_browser_shims_sync
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
  browser-shims)
    shift
    case "${1:-}" in
      sync)
        shift
        cmd_browser_shims_sync "$@"
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
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
  help | -h | --help | "")
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
