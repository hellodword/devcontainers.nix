#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nix run .#load [-- latest]

Load ghcr.io/hellodword/devcontainers-dev:latest from the built OCI layout
into the local Docker daemon.
EOF
}

if (($# == 0)); then
  tag="latest"
elif (($# == 1)); then
  case "$1" in
  -h | --help | help)
    usage
    exit 0
    ;;
  latest)
    tag="latest"
    ;;
  *)
    printf 'load-image: unsupported tag %q (expected latest)\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
else
  usage >&2
  exit 2
fi

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
