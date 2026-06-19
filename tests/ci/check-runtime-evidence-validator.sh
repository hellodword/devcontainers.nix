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
  cat >"$target/ci-plan.json" <<'EOF'
{}
EOF
  cat >"$target/closure-report.json" <<'EOF'
{}
EOF
  cat >"$target/docker-access-report.json" <<'EOF'
{}
EOF
  cat >"$target/env-report.json" <<'EOF'
{}
EOF
  cat >"$target/extensions-index.json" <<'EOF'
{}
EOF
  cat >"$target/extensions-report.json" <<'EOF'
{}
EOF
  cat >"$target/fhs-runtime-report.json" <<'EOF'
{}
EOF
  cat >"$target/graph.json" <<'EOF'
{}
EOF
  cat >"$target/graph-normalized.json" <<'EOF'
{}
EOF
  cat >"$target/graph-duplicates-report.json" <<'EOF'
{}
EOF
  cat >"$target/image-plan.json" <<'EOF'
{}
EOF
  cat >"$target/layer-plan.json" <<'EOF'
{}
EOF
  cat >"$target/metadata-label.json" <<'EOF'
{}
EOF
  cat >"$target/metadata-merged-preview.json" <<'EOF'
{}
EOF
  cat >"$target/metadata-schema-report.json" <<'EOF'
{}
EOF
  cat >"$target/security-report.json" <<'EOF'
{}
EOF
  cat >"$target/smoke-test-plan.json" <<'EOF'
{}
EOF
  cat >"$target/tasks.json" <<'EOF'
{}
EOF
}

build_full_fixture() {
  local base="$1"
  mkdir -p "$base/oci-nix" "$base/oci-nix-dind" "$base/docker-access"
  printf 'full\n' >"$base/mode.txt"
  printf '20260619T000000Z\n' >"$base/generated-at.txt"
  printf './tests/smoke/collect-runtime-evidence.sh full\n' >"$base/invocation.txt"
  cat >"$base/summary.tsv" <<'EOF'
mode	name	exit_code
oci-nix	docker-load	0
oci-nix	docker-inspect	0
oci-nix	docker-run-env	0
oci-nix	docker-run-bash	0
oci-nix	docker-run-task-runner	0
oci-nix-dind	docker-load	0
oci-nix-dind	docker-inspect	0
oci-nix-dind	docker-run-env	0
oci-nix-dind	docker-run-bash	0
oci-nix-dind	docker-run-task-runner	0
docker-access	docker-load	0
docker-access	docker-version	0
docker-access	docker-info	0
docker-access	docker-buildx-version	0
docker-access	docker-compose-version	0
docker-access	docker-task-runner	0
docker-access	docker-process-list	0
docker-access	docker-build-run-smoke	0
docker-access	remote-tcp-explain	0
docker-access	remote-tcp-docker-version	0
EOF

  for section in oci-nix oci-nix-dind; do
    printf 'devcontainer-%s:latest\n' "${section#oci-}" >"$base/$section/image-ref.txt"
    printf '/nix/store/fake-%s.tar.gz\n' "$section" >"$base/$section/oci-path.txt"
    printf '/nix/store/fake-%s-smoke.json\n' "$section" >"$base/$section/smoke-plan-path.txt"
    write_reports "$base/$section/reports"
    make_run_dir "$base" "$section" docker-load "docker load" "Loaded image: devcontainer-${section#oci-}:latest\n"
    make_run_dir "$base" "$section" docker-inspect "docker inspect" "$(cat <<EOF
[{"Config":{"Entrypoint":["/usr/local/bin/devcontainer-entrypoint"],"Cmd":["sleep","infinity"],"Env":["PATH=/usr/local/bin:/bin","EDITOR=vim"],"Labels":{"devcontainer.metadata":"[{\"containerEnv\":{\"PATH\":\"/usr/local/bin:/bin\",\"EDITOR\":\"vim\"},\"remoteUser\":\"vscode\",\"containerUser\":\"vscode\"}]"}}}]
EOF
)"
    make_run_dir "$base" "$section" docker-run-env "docker run env" $'PATH=/usr/local/bin:/bin\nEDITOR=vim\n'
    make_run_dir "$base" "$section" docker-run-bash "docker run bash" $'ok\n'
    make_run_dir "$base" "$section" docker-run-task-runner "docker run devcontainer-task-runner list" $'vscode-extension-projection\tpostCreate\tonce=true\n'
    cat >"$base/$section/reports/tasks.json" <<'EOF'
{"tasks":[{"name":"vscode-extension-projection","phase":"postCreate","once":true}]}
EOF
    cat >"$base/$section/reports/metadata-label.json" <<'EOF'
[{"containerEnv":{"PATH":"/usr/local/bin:/bin","EDITOR":"vim"},"remoteUser":"vscode","containerUser":"vscode"}]
EOF
    cat >"$base/$section/reports/metadata-merged-preview.json" <<'EOF'
{"containerEnv":{"PATH":"/usr/local/bin:/bin","EDITOR":"vim"},"remoteUser":"vscode","containerUser":"vscode"}
EOF
  done

  printf 'devcontainer-nix-dind:latest\n' >"$base/docker-access/image-ref.txt"
  printf '/nix/store/fake-dind.tar.gz\n' >"$base/docker-access/oci-path.txt"
  printf '/var/run/docker.sock\n' >"$base/docker-access/host-docker-socket.txt"
  printf 'tcp://docker.example.internal:2375\n' >"$base/docker-access/remote-docker-host.txt"
  write_reports "$base/docker-access/reports"
  make_run_dir "$base" docker-access docker-load "docker load" "Loaded image: devcontainer-nix-dind:latest\n"
  make_run_dir "$base" docker-access docker-version "docker version" "Client: Docker Engine\nServer: Docker Engine\n"
  make_run_dir "$base" docker-access docker-info "docker info" "Server Version: 28.0.0\n"
  make_run_dir "$base" docker-access docker-buildx-version "docker buildx version" "github.com/docker/buildx v0.21.1\n"
  make_run_dir "$base" docker-access docker-compose-version "docker compose version" "Docker Compose version v2.35.1\n"
  make_run_dir "$base" docker-access docker-task-runner "docker run devcontainer-task-runner list" $'docker-context-init\tpostCreate\tonce=true\nvscode-extension-projection\tpostCreate\tonce=true\n'
  make_run_dir "$base" docker-access docker-process-list "docker run ps -ef" $'UID          PID    PPID  C STIME TTY          TIME CMD\nvscode         1       0  0 00:00 ?        00:00:00 /usr/local/bin/devcontainer-entrypoint /bin/bash -lc ps -ef\nvscode         7       1  0 00:00 ?        00:00:00 ps -ef\n'
  make_run_dir "$base" docker-access docker-build-run-smoke "docker build && docker run" $'ok\n'
  make_run_dir "$base" docker-access remote-tcp-explain "devcontainer-docker-access explain" $'mode=tcp://docker.example.internal:2375\ntls_verify=0\ncert_path=\n'
  make_run_dir "$base" docker-access remote-tcp-docker-version "devcontainer-docker-access docker version" "Client: Docker Engine\nServer: Docker Engine\n"
}

bash -n "$repo_root/tests/smoke/collect-runtime-evidence.sh"
python3 - "$repo_root/tests/ci/check-runtime-evidence.py" <<'EOF'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
compile(source, sys.argv[1], "exec")
EOF

strict_fixture="$tmpdir/strict"
build_full_fixture "$strict_fixture"
python3 "$repo_root/tests/ci/check-runtime-evidence.py" "$strict_fixture" >"$tmpdir/strict.out"
grep -q 'runtime-evidence-check ok' "$tmpdir/strict.out"

tls_fixture="$tmpdir/tls"
build_full_fixture "$tls_fixture"
printf 'tcp://docker.example.internal:2376\n' >"$tls_fixture/docker-access/remote-docker-host.txt"
printf '/tmp/certs\n' >"$tls_fixture/docker-access/remote-docker-certs-dir.txt"
cat >"$tls_fixture/docker-access/remote-tcp-explain/stdout.txt" <<'EOF'
mode=tcp://docker.example.internal:2376
tls_verify=1
cert_path=/run/docker-certs
EOF
python3 "$repo_root/tests/ci/check-runtime-evidence.py" "$tls_fixture" >"$tmpdir/tls.out"
grep -q 'runtime-evidence-check ok' "$tmpdir/tls.out"

skip_fixture="$tmpdir/skip"
build_full_fixture "$skip_fixture"
rm -f "$skip_fixture/docker-access/remote-docker-host.txt" "$skip_fixture/docker-access/remote-docker-certs-dir.txt"
rm -rf "$skip_fixture/docker-access/remote-tcp-explain" "$skip_fixture/docker-access/remote-tcp-docker-version"
cat >"$skip_fixture/docker-access/remote-tcp-skipped.txt" <<'EOF'
remote TCP validation was skipped.
EOF
python3 "$repo_root/tests/ci/check-runtime-evidence.py" "$skip_fixture" --allow-remote-tcp-skip >"$tmpdir/skip.out"
grep -q 'runtime-evidence-check ok' "$tmpdir/skip.out"

if python3 "$repo_root/tests/ci/check-runtime-evidence.py" "$skip_fixture" >"$tmpdir/skip-strict.out" 2>"$tmpdir/skip-strict.err"; then
  echo "expected strict runtime evidence validation to fail when remote TCP evidence is skipped" >&2
  exit 1
fi
grep -q 'remote TCP evidence was skipped' "$tmpdir/skip-strict.err"

echo "runtime-evidence-validator ok"
