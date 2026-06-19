#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  tests/smoke/collect-runtime-evidence.sh oci [image-name] [output-dir]
  tests/smoke/collect-runtime-evidence.sh docker-access [output-dir]
  tests/smoke/collect-runtime-evidence.sh full [output-dir]

examples:
  tests/smoke/collect-runtime-evidence.sh oci nix
  tests/smoke/collect-runtime-evidence.sh docker-access docker-access-evidence
  tests/smoke/collect-runtime-evidence.sh full runtime-evidence

environment:
  DEVCONTAINER_HOST_DOCKER_SOCKET
    Host docker socket to mount into nix-dind. Default: /var/run/docker.sock

  DEVCONTAINER_REMOTE_DOCKER_HOST
  DEVCONTAINER_REMOTE_DOCKER_CERTS_DIR
    Optional remote TCP TLS validation inputs for nix-dind. When both are set,
    the script records helper output and a docker version call routed through
    devcontainer-docker-access with DOCKER_TLS_VERIFY=1.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "$1 is required" >&2
    exit 1
  }
}

timestamp() {
  date -u +%Y%m%dT%H%M%SZ
}

quote_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

run_capture() {
  local section="$1"
  local name="$2"
  local command_text="$3"
  local run_dir="$evidence_dir/$section/$name"
  local status

  mkdir -p "$run_dir"
  printf '%s\n' "$command_text" >"$run_dir/command.txt"

  if bash -lc "$command_text" >"$run_dir/stdout.txt" 2>"$run_dir/stderr.txt"; then
    status=0
    printf '[pass] %s/%s\n' "$section" "$name"
  else
    status=$?
    had_failure=1
    printf '[fail] %s/%s (exit %s)\n' "$section" "$name" "$status"
  fi

  printf '%s\n' "$status" >"$run_dir/exit-code.txt"
  printf '%s\t%s\t%s\n' "$section" "$name" "$status" >>"$summary_file"
}

copy_reports() {
  local image_name="$1"
  local target_dir="$2"
  local reports_path

  reports_path="$(nix build ".#images.${image_name}.reports" --print-out-paths --no-link)"
  mkdir -p "$target_dir"
  cp -L "$reports_path"/*.json "$target_dir"/
  printf '%s\n' "$reports_path" >"$target_dir/source-path.txt"
}

build_oci_path() {
  local image_name="$1"
  nix build ".#images.${image_name}.oci" --print-out-paths --no-link
}

build_smoke_path() {
  local image_name="$1"
  nix build ".#images.${image_name}.smoke" --print-out-paths --no-link
}

collect_oci_runtime() {
  local image_name="$1"
  local section="$2"
  local image_ref="devcontainer-${image_name}:latest"
  local oci_path
  local smoke_path

  oci_path="$(build_oci_path "$image_name")"
  smoke_path="$(build_smoke_path "$image_name")"

  mkdir -p "$evidence_dir/$section"
  printf '%s\n' "$image_ref" >"$evidence_dir/$section/image-ref.txt"
  printf '%s\n' "$oci_path" >"$evidence_dir/$section/oci-path.txt"
  printf '%s\n' "$smoke_path" >"$evidence_dir/$section/smoke-plan-path.txt"

  copy_reports "$image_name" "$evidence_dir/$section/reports"

  run_capture "$section" docker-load "gzip -dc '$oci_path' | docker load"
  run_capture "$section" docker-inspect "docker inspect '$image_ref'"
  run_capture "$section" docker-run-env "docker run --rm '$image_ref' env"
  run_capture "$section" docker-run-bash "docker run --rm '$image_ref' /bin/bash -lc 'echo ok'"
  run_capture "$section" docker-run-task-runner "docker run --rm '$image_ref' devcontainer-task-runner list"
}

collect_docker_access() {
  local section="$1"
  local image_name="nix-dind"
  local image_ref="devcontainer-${image_name}:latest"
  local oci_path
  local socket_path="${DEVCONTAINER_HOST_DOCKER_SOCKET:-/var/run/docker.sock}"
  local build_dir

  oci_path="$(build_oci_path "$image_name")"
  mkdir -p "$evidence_dir/$section"
  printf '%s\n' "$image_ref" >"$evidence_dir/$section/image-ref.txt"
  printf '%s\n' "$oci_path" >"$evidence_dir/$section/oci-path.txt"
  printf '%s\n' "$socket_path" >"$evidence_dir/$section/host-docker-socket.txt"

  copy_reports "$image_name" "$evidence_dir/$section/reports"

  run_capture "$section" docker-load "gzip -dc '$oci_path' | docker load"
  run_capture "$section" docker-version "docker run --rm -v '$socket_path:/var/run/docker.sock' '$image_ref' docker version"
  run_capture "$section" docker-info "docker run --rm -v '$socket_path:/var/run/docker.sock' '$image_ref' docker info"
  run_capture "$section" docker-buildx-version "docker run --rm -v '$socket_path:/var/run/docker.sock' '$image_ref' docker buildx version"
  run_capture "$section" docker-compose-version "docker run --rm -v '$socket_path:/var/run/docker.sock' '$image_ref' docker compose version"
  run_capture "$section" docker-task-runner "docker run --rm -v '$socket_path:/var/run/docker.sock' '$image_ref' devcontainer-task-runner list"

  build_dir="$(mktemp -d)"
  cat >"$build_dir/Dockerfile" <<'EOF'
FROM busybox
RUN echo ok >/ok
CMD ["cat", "/ok"]
EOF
  printf '%s\n' "$build_dir" >"$evidence_dir/$section/build-context.txt"
  run_capture \
    "$section" \
    docker-build-run-smoke \
    "docker run --rm -v '$socket_path:/var/run/docker.sock' -v '$build_dir:/tmp/build' '$image_ref' bash -lc 'docker build -t docker-access-smoke /tmp/build && docker run --rm docker-access-smoke'"
  rm -rf "$build_dir"

  if [ -n "${DEVCONTAINER_REMOTE_DOCKER_HOST:-}" ] && [ -n "${DEVCONTAINER_REMOTE_DOCKER_CERTS_DIR:-}" ]; then
    printf '%s\n' "${DEVCONTAINER_REMOTE_DOCKER_HOST}" >"$evidence_dir/$section/remote-docker-host.txt"
    printf '%s\n' "${DEVCONTAINER_REMOTE_DOCKER_CERTS_DIR}" >"$evidence_dir/$section/remote-docker-certs-dir.txt"
    run_capture \
      "$section" \
      remote-tls-explain \
      "docker run --rm -e DOCKER_HOST='${DEVCONTAINER_REMOTE_DOCKER_HOST}' -e DOCKER_TLS_VERIFY=1 -e DOCKER_CERT_PATH=/run/docker-certs -v '${DEVCONTAINER_REMOTE_DOCKER_CERTS_DIR}:/run/docker-certs:ro' '$image_ref' devcontainer-docker-access explain"
    run_capture \
      "$section" \
      remote-tls-docker-version \
      "docker run --rm -e DOCKER_HOST='${DEVCONTAINER_REMOTE_DOCKER_HOST}' -e DOCKER_TLS_VERIFY=1 -e DOCKER_CERT_PATH=/run/docker-certs -v '${DEVCONTAINER_REMOTE_DOCKER_CERTS_DIR}:/run/docker-certs:ro' '$image_ref' devcontainer-docker-access docker version"
  else
    cat >"$evidence_dir/$section/remote-tls-skipped.txt" <<'EOF'
remote TCP TLS validation was skipped.
Set both DEVCONTAINER_REMOTE_DOCKER_HOST and DEVCONTAINER_REMOTE_DOCKER_CERTS_DIR
to record remote TLS evidence for step 4.8.
EOF
  fi
}

main() {
  local mode="${1:-}"
  local output_dir_arg=""

  case "$mode" in
    oci)
      image_name="${2:-nix}"
      output_dir_arg="${3:-}"
      ;;
    docker-access)
      output_dir_arg="${2:-}"
      ;;
    full)
      output_dir_arg="${2:-}"
      ;;
    -h|--help|help|"")
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac

  require_cmd nix
  require_cmd docker
  require_cmd gzip
  require_cmd cp
  require_cmd date

  if [ -n "$output_dir_arg" ]; then
    evidence_dir="$output_dir_arg"
  else
    evidence_dir="runtime-evidence-${mode}-$(timestamp)"
  fi

  mkdir -p "$evidence_dir"
  summary_file="$evidence_dir/summary.tsv"
  had_failure=0

  printf 'mode\tname\texit_code\n' >"$summary_file"
  printf '%s\n' "$mode" >"$evidence_dir/mode.txt"
  printf '%s\n' "$(timestamp)" >"$evidence_dir/generated-at.txt"
  quote_cmd "$0" "$@" >"$evidence_dir/invocation.txt"

  case "$mode" in
    oci)
      collect_oci_runtime "$image_name" "oci-${image_name}"
      ;;
    docker-access)
      collect_docker_access "docker-access"
      ;;
    full)
      collect_oci_runtime "nix" "oci-nix"
      collect_oci_runtime "nix-dind" "oci-nix-dind"
      collect_docker_access "docker-access"
      ;;
  esac

  if [ "$had_failure" -ne 0 ]; then
    echo "runtime evidence collection finished with failures; inspect $summary_file" >&2
    exit 1
  fi

  echo "runtime evidence collection ok: $evidence_dir"
}

main "$@"
