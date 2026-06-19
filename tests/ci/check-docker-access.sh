#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: tests/ci/check-docker-access.sh <devcontainer-docker-access>" >&2
  exit 1
fi

tool="$1"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fake_docker="$tmpdir/docker-real"
cat >"$fake_docker" <<'EOF'
#!/usr/bin/env bash
printf 'docker-real %s\n' "$*"
EOF
chmod +x "$fake_docker"

if DEVCONTAINER_DOCKER_SOCKET="$tmpdir/missing.sock" \
  "$tool/bin/devcontainer-docker-access" docker version >"$tmpdir/socket.out" 2>"$tmpdir/socket.err"; then
  echo "expected docker helper to fail without daemon configuration" >&2
  exit 1
fi
grep -q 'docker daemon unavailable' "$tmpdir/socket.err"

if DOCKER_HOST=tcp://docker.example.internal:2376 \
  "$tool/bin/devcontainer-docker-access" docker version >"$tmpdir/tcp.out" 2>"$tmpdir/tcp.err"; then
  echo "expected remote tcp helper to require TLS" >&2
  exit 1
fi
grep -q 'remote tcp docker daemon requires TLS' "$tmpdir/tcp.err"

DOCKER_HOST=tcp://docker.example.internal:2376 \
DOCKER_TLS_VERIFY=1 \
DOCKER_CERT_PATH=/run/docker-certs \
DEVCONTAINER_DOCKER_REAL="$fake_docker" \
  "$tool/bin/devcontainer-docker-access" docker version >"$tmpdir/tls.out"
grep -q '^docker-real version$' "$tmpdir/tls.out"

DOCKER_HOST=tcp://docker.example.internal:2376 \
DOCKER_TLS_VERIFY=1 \
DOCKER_CERT_PATH=/run/docker-certs \
  "$tool/bin/devcontainer-docker-access" explain >"$tmpdir/explain.out"
grep -q 'mode=tcp://docker.example.internal:2376' "$tmpdir/explain.out"
grep -q 'tls_verify=1' "$tmpdir/explain.out"
grep -q 'cert_path=/run/docker-certs' "$tmpdir/explain.out"

echo "docker-access-check ok"
