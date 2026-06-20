#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-.}"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

make_run_dir() {
  local base="$1"
  local section="$2"
  local name="$3"
  local command_text="$4"
  local stdout_text="$5"
  local stderr_text="${6:-}"
  mkdir -p "$base/$section/$name"
  printf '%s\n' "$command_text" >"$base/$section/$name/command.txt"
  printf '%s' "$stdout_text" >"$base/$section/$name/stdout.txt"
  printf '%s' "$stderr_text" >"$base/$section/$name/stderr.txt"
  printf '0\n' >"$base/$section/$name/exit-code.txt"
}

write_reports() {
  local target="$1"
  mkdir -p "$target"
  for report in \
    ci-plan closure-report env-report extensions-index extensions-report filesystem-report \
    fhs-runtime-report graph graph-normalized graph-duplicates-report image-plan layer-plan libraries-report \
    metadata-label metadata-merged-preview metadata-schema-report security-report smoke-test-plan tasks
  do
    printf '{}\n' >"$target/$report.json"
  done
}

build_fixture() {
  local base="$1"
  local section="oci-nix-latest"
  mkdir -p "$base/$section"
  printf 'oci\n' >"$base/mode.txt"
  printf '20260619T000000Z\n' >"$base/generated-at.txt"
  printf './tests/smoke/collect-runtime-evidence.sh oci nix-latest\n' >"$base/invocation.txt"
  cat >"$base/summary.tsv" <<'EOF'
mode	name	exit_code
oci-nix-latest	image-load	0
oci-nix-latest	docker-inspect	0
oci-nix-latest	docker-run-env	0
oci-nix-latest	docker-run-bash	0
oci-nix-latest	docker-run-user	0
oci-nix-latest	docker-run-task-runner	0
oci-nix-latest	docker-run-required-tools	0
EOF

  printf 'ghcr.io/hellodword/devcontainers-nix:latest\n' >"$base/$section/image-ref.txt"
  printf '/nix/store/fake-image-nix.json\n' >"$base/$section/image-path.txt"
  printf '/nix/store/fake-nix-smoke.json\n' >"$base/$section/smoke-plan-path.txt"
  write_reports "$base/$section/reports"
  make_run_dir "$base" "$section" image-load "nix run .#load-nix-latest" "Copy to Docker daemon image ghcr.io/hellodword/devcontainers-nix:latest\n"
  make_run_dir "$base" "$section" docker-inspect "docker inspect" "$(cat <<'EOF'
[{"Config":{"User":"vscode","WorkingDir":"/workspaces","Entrypoint":["/usr/local/bin/devcontainer-entrypoint"],"Cmd":["sleep","infinity"],"Env":["PATH=/usr/local/bin:/bin","HOME=/home/vscode","EDITOR=vim"],"Labels":{"devcontainer.metadata":"[{\"containerEnv\":{\"PATH\":\"/usr/local/bin:/bin\",\"HOME\":\"/home/vscode\",\"EDITOR\":\"vim\"},\"remoteUser\":\"vscode\",\"containerUser\":\"vscode\"}]"}}}]
EOF
)"
  make_run_dir "$base" "$section" docker-run-env "docker run env" $'PATH=/usr/local/bin:/bin\nHOME=/home/vscode\nEDITOR=vim\n'
  make_run_dir "$base" "$section" docker-run-bash "docker run bash" $'ok\n'
  make_run_dir "$base" "$section" docker-run-user "docker run id vscode" $'uid=1000(vscode) gid=1000(vscode) groups=1000(vscode)\n'
  make_run_dir "$base" "$section" docker-run-task-runner "docker run devcontainer-task-runner list" $'vscode-extension-projection\tpostCreate\tonce=true\n'
  make_run_dir "$base" "$section" docker-run-required-tools "docker run command -v" $'/bin/docker\n/bin/codex\n/bin/nix-locate\n'
  cat >"$base/$section/reports/metadata-label.json" <<'EOF'
[{"containerEnv":{"PATH":"/usr/local/bin:/bin","HOME":"/home/vscode","EDITOR":"vim"},"remoteUser":"vscode","containerUser":"vscode"}]
EOF
}

bash -n "$repo_root/tests/smoke/collect-runtime-evidence.sh"
python3 - "$repo_root/tests/ci/check-runtime-evidence.py" <<'EOF'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
EOF

fixture="$tmpdir/fixture"
build_fixture "$fixture"
python3 "$repo_root/tests/ci/check-runtime-evidence.py" "$fixture" >"$tmpdir/out"
grep -q 'runtime-evidence-check ok' "$tmpdir/out"

echo "runtime-evidence-validator ok"
