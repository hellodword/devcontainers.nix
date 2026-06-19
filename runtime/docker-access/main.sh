set -euo pipefail

docker_real="${DEVCONTAINER_DOCKER_REAL:-docker-real}"

usage() {
  cat <<'EOF'
devcontainer-docker-access init
devcontainer-docker-access docker [args...]
EOF
}

run_docker() {
  if [ "${DOCKER_HOST:-}" != "${DOCKER_HOST#tcp://}" ]; then
    exec "$docker_real" "$@"
  fi

  socket="/var/run/docker.sock"
  if [ -S "$socket" ] && [ -r "$socket" ]; then
    exec "$docker_real" "$@"
  fi

  if [ -S "$socket" ] && command -v sudo >/dev/null 2>&1; then
    exec sudo -E "$docker_real" "$@"
  fi

  cat >&2 <<'EOF'
docker daemon unavailable
- host socket mode: mount /var/run/docker.sock
- remote tcp tls mode: set DOCKER_HOST=tcp://host:2376, DOCKER_TLS_VERIFY=1, DOCKER_CERT_PATH=/run/docker-certs
EOF
  exit 1
}

cmd="${1:-}"
case "$cmd" in
  init)
    mkdir -p "${HOME}/.docker"
    ;;
  docker)
    shift
    run_docker "$@"
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
