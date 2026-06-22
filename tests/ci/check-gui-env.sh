#!/usr/bin/env bash
set -euo pipefail

gui_env="${DEVCONTAINER_GUI_ENV_TOOL:?DEVCONTAINER_GUI_ENV_TOOL is required}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
export HOME="$tmpdir/home"
mkdir -p "$HOME"
bash_bin="$(command -v bash)"
isolated_path="$(dirname "$bash_bin")"

require_grep() {
  local pattern="$1"
  local file="$2"
  if ! grep -q -- "$pattern" "$file"; then
    printf 'missing pattern %s in %s\n' "$pattern" "$file" >&2
    cat "$file" >&2
    exit 1
  fi
}

make_unix_socket() {
  python3 - "$1" <<'PY'
import os
import socket
import sys

path = sys.argv[1]
try:
    os.unlink(path)
except FileNotFoundError:
    pass

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.bind(path)
sock.listen(1)
sock.close()
PY
}

run_gui_refresh() {
  local runtime_dir="$1"
  local scan_dir="$runtime_dir/scan"
  shift
  mkdir -p "$scan_dir"
  env -i HOME="$HOME" PATH="$isolated_path" XDG_RUNTIME_DIR="$runtime_dir" \
    DEVCONTAINER_GUI_WAYLAND_SCAN_DIRS="$scan_dir" "$@" \
    "$gui_env/bin/devcontainer-gui-env" refresh
}

source_gui_env_assert() {
  local env_file="$1"
  local script="$2"
  shift 2
  env -i HOME="$HOME" PATH="$isolated_path" "$@" "$bash_bin" -c '. "$1"; eval "$2"' _ "$env_file" "$script"
}

gui_runtime="$tmpdir/gui-runtime"
mkdir -p "$gui_runtime"

run_gui_refresh "$gui_runtime" >"$tmpdir/gui-none.txt"
require_grep '^backend=none$' "$tmpdir/gui-none.txt"
source_gui_env_assert "$gui_runtime/devcontainer-gui-env.sh" \
  'test -z "${QT_QPA_PLATFORM:-}" && test -z "${GDK_BACKEND:-}" && test -z "${NIXOS_OZONE_WL:-}"'

run_gui_refresh "$gui_runtime" DISPLAY=:42 >"$tmpdir/gui-x11.txt"
require_grep '^backend=x11$' "$tmpdir/gui-x11.txt"
source_gui_env_assert "$gui_runtime/devcontainer-gui-env.sh" \
  'test "$XDG_SESSION_TYPE" = x11 && test "$GDK_BACKEND" = x11 && test "$QT_QPA_PLATFORM" = xcb && test "$SDL_VIDEODRIVER" = x11 && test "$CLUTTER_BACKEND" = x11 && test -z "${MOZ_ENABLE_WAYLAND:-}" && test -z "${NIXOS_OZONE_WL:-}" && test "$DISPLAY" = :42' \
  DISPLAY=:42 MOZ_ENABLE_WAYLAND=1 NIXOS_OZONE_WL=1

make_unix_socket "$gui_runtime/wayland-0"
run_gui_refresh "$gui_runtime" WAYLAND_DISPLAY=wayland-0 DISPLAY=:42 >"$tmpdir/gui-wayland.txt"
require_grep '^backend=wayland$' "$tmpdir/gui-wayland.txt"
source_gui_env_assert "$gui_runtime/devcontainer-gui-env.sh" \
  'test "$XDG_SESSION_TYPE" = wayland && test "$GDK_BACKEND" = wayland,x11 && test "$QT_QPA_PLATFORM" = "wayland;xcb" && test "$SDL_VIDEODRIVER" = wayland && test "$CLUTTER_BACKEND" = wayland && test "$MOZ_ENABLE_WAYLAND" = 1 && test "$NIXOS_OZONE_WL" = 1'

run_gui_refresh "$gui_runtime" DEVCONTAINER_GUI_BACKEND=x11 WAYLAND_DISPLAY=wayland-0 DISPLAY=:42 >"$tmpdir/gui-force-x11.txt"
require_grep '^backend=x11$' "$tmpdir/gui-force-x11.txt"

run_gui_refresh "$gui_runtime" WAYLAND_DISPLAY=missing DISPLAY=:42 >"$tmpdir/gui-invalid-wayland-fallback.txt"
require_grep '^backend=x11$' "$tmpdir/gui-invalid-wayland-fallback.txt"

run_gui_refresh "$gui_runtime" DEVCONTAINER_GUI_ENV=0 WAYLAND_DISPLAY=wayland-0 DISPLAY=:42 >"$tmpdir/gui-disabled.txt"
require_grep '^enabled=0$' "$tmpdir/gui-disabled.txt"
require_grep '^backend=disabled$' "$tmpdir/gui-disabled.txt"
source_gui_env_assert "$gui_runtime/devcontainer-gui-env.sh" \
  'test -z "${QT_QPA_PLATFORM:-}" && test -z "${GDK_BACKEND:-}" && test -z "${NIXOS_OZONE_WL:-}"' \
  QT_QPA_PLATFORM=xcb GDK_BACKEND=x11 NIXOS_OZONE_WL=1

echo "gui-env-check ok"
