#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nix run .#load -- <latest|agent>

Load the selected image variant from the shared OCI layout into the local Docker daemon
as ghcr.io/hellodword/devcontainers-dev:<latest|agent>.
EOF
}

if (($# != 1)); then
  usage >&2
  exit 2
fi

case "$1" in
-h | --help | help)
  usage
  exit 0
  ;;
latest | agent)
  tag="$1"
  ;;
*)
  printf 'load-image: unsupported variant %q (expected latest or agent)\n' "$1" >&2
  usage >&2
  exit 2
  ;;
esac

if [[ -z "${OCI_DIR:-}" || ! -f "${OCI_DIR}/index.json" ]]; then
  printf 'load-image: OCI_DIR must point to a valid OCI layout directory\n' >&2
  exit 1
fi

target_ref="ghcr.io/hellodword/devcontainers-dev:${tag}"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/devcontainer-load.XXXXXX")"
trap 'rm -rf -- "$tmpdir"' EXIT

printf 'Loading %s from %s:%s\n' "$target_ref" "$OCI_DIR" "$tag"
if skopeo --tmpdir "$tmpdir" --insecure-policy copy \
  "oci:${OCI_DIR}:${tag}" \
  "docker-daemon:${target_ref}"; then
  exit 0
fi

printf 'Direct docker-daemon copy unavailable; streaming via docker-archive...\n' >&2
archive="$tmpdir/image.tar"
skopeo --tmpdir "$tmpdir" --insecure-policy copy \
  "oci:${OCI_DIR}:${tag}" \
  "docker-archive:${archive}:${target_ref}"
docker load -i "$archive"
