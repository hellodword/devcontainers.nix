#!/usr/bin/env bash
set -euo pipefail

if command -v devcontainer-gui-env >/dev/null 2>&1; then
  devcontainer-gui-env refresh >/dev/null 2>&1 || true
  gui_env_file="${DEVCONTAINER_GUI_ENV_FILE:-${XDG_RUNTIME_DIR}/devcontainer-gui-env.sh}"
  if [ -r "$gui_env_file" ]; then
    # shellcheck disable=SC1090
    . "$gui_env_file"
  fi
fi

exec "$@"
