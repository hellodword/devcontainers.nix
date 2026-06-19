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
ln -sf "$tool/bin/devcontainer-docker-access" "$tmpdir/docker"

if DEVCONTAINER_DOCKER_SOCKET="$tmpdir/missing.sock" \
  "$tool/bin/devcontainer-docker-access" docker version >"$tmpdir/socket.out" 2>"$tmpdir/socket.err"; then
  echo "expected docker helper to fail without daemon configuration" >&2
  exit 1
fi
grep -q 'docker daemon unavailable' "$tmpdir/socket.err"

DOCKER_HOST=tcp://docker.example.internal:2375 \
DEVCONTAINER_DOCKER_REAL="$fake_docker" \
  "$tool/bin/devcontainer-docker-access" docker version >"$tmpdir/tcp.out"
grep -q '^docker-real version$' "$tmpdir/tcp.out"

DOCKER_HOST=tcp://docker.example.internal:2375 \
DEVCONTAINER_DOCKER_REAL="$fake_docker" \
  "$tmpdir/docker" version >"$tmpdir/alias.out"
grep -q '^docker-real version$' "$tmpdir/alias.out"

if DOCKER_HOST=tcp://docker.example.internal:2376 \
DOCKER_TLS_VERIFY=1 \
  "$tool/bin/devcontainer-docker-access" docker version >"$tmpdir/tls-missing-path.out" 2>"$tmpdir/tls-missing-path.err"; then
  echo "expected remote tcp helper with TLS to require DOCKER_CERT_PATH" >&2
  exit 1
fi
grep -q 'requires DOCKER_CERT_PATH' "$tmpdir/tls-missing-path.err"

DOCKER_HOST=tcp://docker.example.internal:2375 \
  "$tool/bin/devcontainer-docker-access" explain >"$tmpdir/explain-tcp.out"
grep -q 'mode=tcp://docker.example.internal:2375' "$tmpdir/explain-tcp.out"
grep -q 'tls_verify=0' "$tmpdir/explain-tcp.out"

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
