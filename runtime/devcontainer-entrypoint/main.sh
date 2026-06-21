set -euo pipefail

current_user="$(id -un 2>/dev/null || true)"
if [ "$current_user" != "vscode" ]; then
  echo "devcontainers.nix images must run as the vscode user; remove containerUser/remoteUser overrides from devcontainer.json" >&2
  exit 126
fi

if command -v devcontainer-gui-env >/dev/null 2>&1; then
  devcontainer-gui-env refresh >/dev/null 2>&1 || true
  gui_env_file="${DEVCONTAINER_GUI_ENV_FILE:-${XDG_RUNTIME_DIR:-/run/user/1000}/devcontainer-gui-env.sh}"
  if [ -r "$gui_env_file" ]; then
    # shellcheck disable=SC1090
    . "$gui_env_file"
  fi
  unset gui_env_file
fi

if [ "$#" -eq 0 ]; then
  exec sleep infinity
fi

exec "$@"
