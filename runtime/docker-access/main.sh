set -euo pipefail

docker_real="${DEVCONTAINER_DOCKER_REAL:-docker-real}"
prog_name="$(basename "$0")"

usage() {
  cat <<'EOF'
devcontainer-docker-access init
devcontainer-docker-access docker [args...]
devcontainer-docker-access explain
EOF
}

run_docker() {
  host="${DOCKER_HOST:-}"
  if [ "$host" != "${host#tcp://}" ]; then
    if [ "${DOCKER_TLS_VERIFY:-0}" = "1" ] && [ -z "${DOCKER_CERT_PATH:-}" ]; then
      cat >&2 <<'EOF'
remote tcp docker daemon with TLS requires DOCKER_CERT_PATH
- set DOCKER_CERT_PATH=/run/docker-certs
EOF
      exit 1
    fi
    exec "$docker_real" "$@"
  fi

  socket="${DEVCONTAINER_DOCKER_SOCKET:-/var/run/docker.sock}"
  if [ -S "$socket" ] && [ -r "$socket" ] && [ -w "$socket" ]; then
    exec "$docker_real" "$@"
  fi

  if [ -S "$socket" ] && command -v sudo >/dev/null 2>&1; then
    exec sudo -E "$docker_real" "$@"
  fi

  cat >&2 <<'EOF'
docker daemon unavailable
- host socket mode: mount ${DEVCONTAINER_DOCKER_SOCKET:-/var/run/docker.sock}
- remote tcp mode: set DOCKER_HOST=tcp://host:2375
- optional TLS: set DOCKER_TLS_VERIFY=1 and DOCKER_CERT_PATH=/run/docker-certs
EOF
  exit 1
}

cmd="${1:-}"
if [ "$prog_name" = "docker" ]; then
  run_docker "$@"
fi

case "$cmd" in
  init)
    mkdir -p "${HOME}/.docker"
    ;;
  explain)
    cat <<EOF
mode=${DOCKER_HOST:-unix:///var/run/docker.sock}
tls_verify=${DOCKER_TLS_VERIFY:-0}
cert_path=${DOCKER_CERT_PATH:-}
EOF
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
