set -euo pipefail

if [ "$#" -eq 0 ]; then
  exec sleep infinity
fi

exec "$@"
