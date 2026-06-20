set -euo pipefail

current_user="$(id -un 2>/dev/null || true)"
if [ "$current_user" != "vscode" ]; then
  echo "devcontainers.nix images must run as the vscode user; remove containerUser/remoteUser overrides from devcontainer.json" >&2
  exit 126
fi

if [ "$#" -eq 0 ]; then
  exec sleep infinity
fi

exec "$@"
