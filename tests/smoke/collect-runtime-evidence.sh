#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  tests/smoke/collect-runtime-evidence.sh oci [image-name] [output-dir]
  tests/smoke/collect-runtime-evidence.sh full [output-dir]

examples:
  tests/smoke/collect-runtime-evidence.sh oci nix
  tests/smoke/collect-runtime-evidence.sh full runtime-evidence

notes:
  Images are loaded with nix2container through `nix run .#load-<image>`.
  Docker daemon smoke for the Docker CLI is handled by tests/smoke/run-plan.sh.
  Set DOCKER_HOST=tcp://... before run-plan.sh to validate a remote daemon.
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

build_image_path() {
  local image_name="$1"
  nix build ".#images.${image_name}.oci" --print-out-paths --no-link
}

build_smoke_path() {
  local image_name="$1"
  nix build ".#images.${image_name}.smoke" --print-out-paths --no-link
}

collect_oci_runtime() {
  local image_name="$1"
  local section="oci-${image_name}"
  local image_ref="devcontainer-${image_name}:latest"
  local image_path
  local smoke_path

  image_path="$(build_image_path "$image_name")"
  smoke_path="$(build_smoke_path "$image_name")"

  mkdir -p "$evidence_dir/$section"
  printf '%s\n' "$image_ref" >"$evidence_dir/$section/image-ref.txt"
  printf '%s\n' "$image_path" >"$evidence_dir/$section/image-path.txt"
  printf '%s\n' "$smoke_path" >"$evidence_dir/$section/smoke-plan-path.txt"

  copy_reports "$image_name" "$evidence_dir/$section/reports"

  run_capture "$section" image-load "nix run '.#load-${image_name}'"
  run_capture "$section" docker-inspect "docker inspect '$image_ref'"
  run_capture "$section" docker-run-env "docker run --rm '$image_ref' env"
  run_capture "$section" docker-run-bash "docker run --rm '$image_ref' /bin/bash -lc 'echo ok'"
  run_capture "$section" docker-run-user "docker run --rm '$image_ref' id vscode"
  run_capture "$section" docker-run-task-runner "docker run --rm '$image_ref' devcontainer-task-runner list"
  run_capture "$section" docker-run-required-tools "docker run --rm '$image_ref' bash -lc 'command -v docker && command -v codex && command -v nix-locate'"
}

main() {
  local mode="${1:-}"
  local output_dir_arg=""
  local image_name=""
  local images=(
    nix
    python
    nodejs
    go
    rust
    python-web
    go-web
    rust-web
    flutter
  )

  case "$mode" in
    oci)
      image_name="${2:-nix}"
      output_dir_arg="${3:-}"
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
      collect_oci_runtime "$image_name"
      ;;
    full)
      for image_name in "${images[@]}"; do
        collect_oci_runtime "$image_name"
      done
      ;;
  esac

  if [ "$had_failure" -ne 0 ]; then
    echo "runtime evidence collection finished with failures; inspect $summary_file" >&2
    exit 1
  fi

  echo "runtime evidence collection ok: $evidence_dir"
}

main "$@"
