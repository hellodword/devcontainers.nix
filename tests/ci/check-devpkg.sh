#!/usr/bin/env bash
set -euo pipefail

devpkg="${DEVCONTAINER_DEVPKG:?DEVCONTAINER_DEVPKG is required}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"
export FAKE_NIX_STATE="$tmpdir/fake-nix-state"
export FAKE_NIX_PYTHON="$(command -v python3)"
export DEVPKG_NIXPKGS_REF="${DEVPKG_NIXPKGS_REF:-path:/fake-nixpkgs}"
fake_nix="$tmpdir/fake-nix/bin/nix"
mkdir -p "$(dirname "$fake_nix")" "$FAKE_NIX_STATE"

bash_bin="$(command -v bash)"
printf '#!%s\n' "$bash_bin" >"$fake_nix"
cat >>"$fake_nix" <<'EOF'
set -euo pipefail

state_dir="${FAKE_NIX_STATE:?FAKE_NIX_STATE is required}"
python_bin="${FAKE_NIX_PYTHON:?FAKE_NIX_PYTHON is required}"
system="x86_64-linux"

profile_key() {
  local profile="${1:-main}"
  profile="${profile//\//_}"
  profile="${profile//:/_}"
  printf '%s\n' "$profile"
}

state_file() {
  local key
  key="$(profile_key "${1:-main}")"
  printf '%s/%s.json\n' "$state_dir" "$key"
}

ensure_state() {
  local file="$1"
  if [ ! -f "$file" ]; then
    mkdir -p "$(dirname "$file")"
    printf '{"elements":{}}\n' >"$file"
  fi
}

profile_json() {
  local profile="${1:-main}"
  local file
  file="$(state_file "$profile")"
  ensure_state "$file"
  cat "$file"
}

add_installable() {
  local profile="$1"
  local installable="$2"
  local file
  file="$(state_file "$profile")"
  ensure_state "$file"
  "$python_bin" - "$file" "$profile" "$installable" "$system" <<'PY'
import json
import os
import sys

state_path, profile, installable, system = sys.argv[1:]
with open(state_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

spec = installable
if "#" in spec:
    spec = spec.split("#", 1)[1]
outputs = ["out"]
if "^" in spec:
    spec, output_text = spec.split("^", 1)
    outputs = [part for part in output_text.split(",") if part]
key = spec.split(".")[-1]
data.setdefault("elements", {})[key] = {
    "attrPath": f"legacyPackages.{system}.{spec}",
    "outputs": outputs,
}
with open(state_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, sort_keys=True)
    handle.write("\n")

if profile != "main":
    if any(output in outputs for output in ("out", "lib")):
        os.makedirs(os.path.join(profile, "lib"), exist_ok=True)
        open(os.path.join(profile, "lib", "libz.so"), "a", encoding="utf-8").close()
    if "dev" in outputs:
        os.makedirs(os.path.join(profile, "include"), exist_ok=True)
        open(os.path.join(profile, "include", "zlib.h"), "a", encoding="utf-8").close()
PY
}

remove_element() {
  local profile="$1"
  local name="$2"
  local file
  file="$(state_file "$profile")"
  ensure_state "$file"
  "$python_bin" - "$file" "$profile" "$name" <<'PY'
import json
import os
import shutil
import sys

state_path, profile, name = sys.argv[1:]
with open(state_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
data.setdefault("elements", {}).pop(name, None)
with open(state_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, sort_keys=True)
    handle.write("\n")
if profile != "main" and not data["elements"]:
    shutil.rmtree(os.path.join(profile, "lib"), ignore_errors=True)
    shutil.rmtree(os.path.join(profile, "include"), ignore_errors=True)
PY
}

cmd="${1:-}"
case "$cmd" in
  eval)
    shift
    if [ "$*" = "--impure --expr builtins.currentSystem --raw" ]; then
      printf '%s\n' "$system"
      exit 0
    fi
    case "$*" in
      *".zlib.outputs"*)
        printf '["out","dev"]\n'
        exit 0
        ;;
      *)
        printf 'fake nix eval unsupported: %s\n' "$*" >&2
        exit 1
        ;;
    esac
    ;;
  profile)
    shift
    subcmd="${1:-}"
    shift || true
    profile="main"
    args=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --impure | --json | --no-pretty)
          shift
          ;;
        --profile)
          profile="$2"
          shift 2
          ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done
    case "$subcmd" in
      add)
        for installable in "${args[@]}"; do
          add_installable "$profile" "$installable"
        done
        ;;
      list)
        profile_json "$profile"
        ;;
      remove)
        for name in "${args[@]}"; do
          remove_element "$profile" "$name"
        done
        ;;
      *)
        printf 'fake nix profile unsupported subcommand: %s\n' "$subcmd" >&2
        exit 1
        ;;
    esac
    ;;
  search)
    exit 0
    ;;
  *)
    printf 'fake nix unsupported command: %s\n' "$cmd" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake_nix"

require_grep() {
  local pattern="$1"
  local file="$2"
  if ! grep -q -- "$pattern" "$file"; then
    printf 'missing pattern %s in %s\n' "$pattern" "$file" >&2
    cat "$file" >&2
    exit 1
  fi
}

completion_file="$devpkg/share/bash-completion/completions/devpkg"
test -r "$completion_file"
"$devpkg/bin/devpkg" complete commands ad >"$tmpdir/devpkg-complete-commands.txt"
require_grep '^add$' "$tmpdir/devpkg-complete-commands.txt"
"$devpkg/bin/devpkg" complete outputs d >"$tmpdir/devpkg-complete-outputs.txt"
require_grep '^dev$' "$tmpdir/devpkg-complete-outputs.txt"

project_root="$tmpdir/project"
(
  export HOME="$project_root/home"
  export XDG_CONFIG_HOME="$project_root/config"
  export XDG_DATA_HOME="$project_root/data"
  export XDG_STATE_HOME="$project_root/state"
  export DEVPKG_RUNTIME_LIBRARY_PROFILE="$project_root/runtime-libraries/profile"
  export DEVPKG_BUILD_LIBRARY_PROFILE="$project_root/build-libraries/profile"
  export DEVPKG_NIX_BIN="$fake_nix"
  export PATH="$HOME/.nix-profile/bin:$XDG_DATA_HOME/nix-profile/bin:$PATH"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

  "$devpkg/bin/devpkg" add cowsay
  "$devpkg/bin/devpkg" list >"$tmpdir/devpkg-list.txt"
  grep -q '^cowsay[[:space:]]' "$tmpdir/devpkg-list.txt"
  grep -q 'legacyPackages\..*\.cowsay$' "$tmpdir/devpkg-list.txt"
  "$devpkg/bin/devpkg" complete installed main cow >"$tmpdir/devpkg-complete-installed.txt"
  require_grep '^cowsay$' "$tmpdir/devpkg-complete-installed.txt"
  "$devpkg/bin/devpkg" remove cowsay
  test -z "$("$devpkg/bin/devpkg" list)"

  "$devpkg/bin/devpkg" add-lib zlib
  "$devpkg/bin/devpkg" list-lib >"$tmpdir/devpkg-list-lib.txt"
  grep -q '^zlib[[:space:]]' "$tmpdir/devpkg-list-lib.txt"
  grep -q 'legacyPackages\..*\.zlib' "$tmpdir/devpkg-list-lib.txt"
  "$devpkg/bin/devpkg" complete installed runtime zl >"$tmpdir/devpkg-complete-runtime-lib.txt"
  require_grep '^zlib$' "$tmpdir/devpkg-complete-runtime-lib.txt"
  test -e "$DEVPKG_RUNTIME_LIBRARY_PROFILE/lib/libz.so"
  test ! -e "$DEVPKG_RUNTIME_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-lib zlib
  test -z "$("$devpkg/bin/devpkg" list-lib)"

  "$devpkg/bin/devpkg" add-dev-lib zlib
  "$devpkg/bin/devpkg" list-dev-lib >"$tmpdir/devpkg-list-dev-lib.txt"
  grep -q '^zlib[[:space:]]' "$tmpdir/devpkg-list-dev-lib.txt"
  grep -q 'legacyPackages\..*\.zlib' "$tmpdir/devpkg-list-dev-lib.txt"
  grep -q 'out,dev' "$tmpdir/devpkg-list-dev-lib.txt"
  "$devpkg/bin/devpkg" complete installed build zl >"$tmpdir/devpkg-complete-build-lib.txt"
  require_grep '^zlib$' "$tmpdir/devpkg-complete-build-lib.txt"
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/lib/libz.so"
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-dev-lib zlib
  test -z "$("$devpkg/bin/devpkg" list-dev-lib)"

  "$devpkg/bin/devpkg" add-dev-lib --outputs out,dev zlib
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-dev-lib zlib

  "$devpkg/bin/devpkg" add-dev-lib --raw "$DEVPKG_NIXPKGS_REF#zlib^out,dev"
  test -e "$DEVPKG_BUILD_LIBRARY_PROFILE/include/zlib.h"
  "$devpkg/bin/devpkg" remove-dev-lib zlib
)

echo "devpkg-check ok"
