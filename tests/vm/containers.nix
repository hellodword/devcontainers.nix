# Workflow 1: Container runtime contract, metadata & cache-layout parity, 100ms cache probes,
# thin UID/GID derivation, offline devpkg, single-user Nix build + GC survival, and gVisor.
{
  pkgs,
  core,
  inputs,
  images,
}:
let
  goPkg = pkgs.go_latest or pkgs.go;
  nodePkg = pkgs.nodejs_latest or pkgs.nodejs;
  expectedStorePaths = builtins.toJSON {
    nixpkgs = "${inputs.nixpkgs.outPath}";
    rustOverlay = "${inputs.rust-overlay.outPath}";
    rustToolchain = "${images.rustToolchain}";
    bash = "${pkgs.bash}/bin/bash";
    gcc = "${pkgs.gcc}";
    go = "${goPkg}";
    nodejs = "${nodePkg}";
    python3 = "${pkgs.python3}";
    stdenv = "${pkgs.stdenv}";
  };

  concurrentLifecyclePy = pkgs.writeText "check-concurrent-lifecycle.py" ''
    import os
    import pathlib
    import subprocess
    import tempfile

    for trial in range(5):
        with tempfile.TemporaryDirectory(prefix=f"home-race-{trial}-") as temp_home:
            env = dict(os.environ, HOME=temp_home)
            for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME"):
                env.pop(key, None)
            procs = [
                subprocess.Popen(["devcontainer-task-runner", "run", "postCreate"], env=env)
                for _ in range(4)
            ]
            codes = [proc.wait(timeout=30) for proc in procs]
            assert codes == [0, 0, 0, 0], (trial, codes)
            for sub in (".vscode-server/extensions", ".vscode-server-insiders/extensions", ".vscode-remote/extensions"):
                entries = list((pathlib.Path(temp_home) / sub).iterdir())
                assert len(entries) == 26 and all(e.is_symlink() for e in entries), (trial, sub, len(entries))

    procs = [
        *[subprocess.Popen(["devcontainer-task-runner", "run", "postCreate"]) for _ in range(4)],
        *[subprocess.Popen(["devcontainer-task-runner", "run", "postStart"]) for _ in range(2)],
    ]
    codes = [proc.wait(timeout=30) for proc in procs]
    assert codes == [0, 0, 0, 0, 0, 0], codes
    status_out = subprocess.check_output(["devcontainer-task-runner", "status"], text=True)
    assert status_out.splitlines() == ["postCreate\tdone", "postStart\tdone"], status_out
    for root in ("/home/vscode/.vscode-server/extensions", "/home/vscode/.vscode-server-insiders/extensions", "/home/vscode/.vscode-remote/extensions"):
        entries = list(pathlib.Path(root).iterdir())
        assert len(entries) == 26 and all(e.is_symlink() for e in entries), (root, len(entries))
  '';
in
core.lib.testing.mkTest pkgs (_: {
  name = "devcontainers-containers-workflow";
  globalTimeout = 2400;
  qemu.forceAccel = true;

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [
        (core.lib.testing.mkContainerHostModule {
          user = "desktop";
          uid = 1000;
          gid = 1000;
        })
      ];

      users.users.desktop.group = "desktop";

      virtualisation = {
        cores = 4;
        memorySize = 8192;
        diskSize = 16384;
        emptyDiskImages = [
          {
            size = 65536;
            driveConfig.driveExtraOpts.cache = "unsafe";
          }
        ];
        fileSystems."/var/lib/docker" = {
          device = "/dev/vdb";
          fsType = "ext4";
          autoFormat = true;
          options = [ "noatime" ];
        };
        qemu.options = [ "-cpu host" ];
      };

      networking.firewall.enable = false;

      environment.systemPackages = [
        pkgs.python3
        pkgs.curl
        pkgs.jq
        pkgs.skopeo
      ];
    };

  testScript = ''
    import hashlib
    import json
    import runpy
    import shlex

    runtime = runpy.run_path("${core.lib.testing.runtimePy}")

    OCI_DIR = ${builtins.toJSON "${images.oci}"}
    CONCURRENT_LIFECYCLE_PY = ${builtins.toJSON "${concurrentLifecyclePy}"}
    EXPECTED_PATHS = json.loads(${builtins.toJSON expectedStorePaths})
    IMAGE_REF = "ghcr.io/hellodword/devcontainers-dev:latest"

    def q(val: str) -> str:
        return shlex.quote(str(val))

    def as_desktop(cmd: str) -> str:
        return "su - desktop -c " + q(cmd)

    captures = [
        (machine, "docker", "journalctl -u docker --no-pager -n 200"),
        (machine, "containers", "su - desktop -c 'docker ps -a'"),
    ]

    with runtime["scenario"]([machine], captures):
      start_all()
      machine.succeed("findmnt -n /var/lib/docker | grep -F /dev/vdb")
      machine.wait_for_unit("docker.service")
      machine.wait_until_succeeds(as_desktop("docker info >/dev/null"), timeout=60)

      with subtest("1. Import image and verify runc runtime contract"):
          machine.succeed(
              as_desktop(
                  f"tmpdir=$(mktemp -d) && trap 'rm -rf \"$tmpdir\"' EXIT && "
                  f"skopeo --tmpdir \"$tmpdir\" --insecure-policy copy oci:{q(OCI_DIR)}:latest docker-daemon:{IMAGE_REF}"
              ),
              timeout=600,
          )

          # Default vscode (1000:1000) identity, /workspaces, XDG, and machine-id.
          machine.succeed(
              as_desktop(
                  f"docker run --rm {IMAGE_REF} bash -euo pipefail -c "
                  + q(
                      'test "$(id -un)" = vscode && '
                      'test "$(id -u)" = 1000 && '
                      'test "$(id -gn)" = vscode && '
                      'test "$(id -g)" = 1000 && '
                      'test "$PWD" = /workspaces && '
                      'test "$(stat -c %a /workspaces)" = 1777 && '
                      'test "$HOME" = /home/vscode && '
                      'test "$XDG_RUNTIME_DIR" = /run/user/1000 && '
                      'test "$(stat -c %a "$XDG_RUNTIME_DIR")" = 700 && '
                      'test -s /etc/machine-id && '
                      'cmp -s /etc/machine-id /var/lib/dbus/machine-id'
                  )
              ),
              timeout=60,
          )

          # Reject --user 0 with exact exit code 126.
          rc, out = machine.execute(as_desktop(f"docker run --rm --user 0 {IMAGE_REF} id 2>&1"), timeout=30)
          assert rc == 126, f"Expected exit 126 for --user 0, got rc={rc}: {out!r}"

          # One-shot command argument passthrough (spaces & special characters) + exit code preservation.
          passthrough = machine.succeed(
              as_desktop(
                  f"docker run --rm {IMAGE_REF} bash -c 'printf \"%s|%s\\n\" \"$1\" \"$2\"' _ "
                  + q("hello world")
                  + " "
                  + q('$HOME "quoted" !')
              ),
              timeout=30,
          ).strip()
          assert passthrough == 'hello world|$HOME "quoted" !', f"Unexpected passthrough: {passthrough!r}"

          rc_custom, _ = machine.execute(as_desktop(f"docker run --rm {IMAGE_REF} bash -c 'exit 42'"), timeout=30)
          assert rc_custom == 42, f"Expected exit code 42 passthrough, got {rc_custom}"

          # Interactive PTY check: wait for interactive bash prompt, then verify alias ll and bash completion.
          pty_script = f"""
    import os, pty, select, subprocess, time
    master, slave = pty.openpty()
    proc = subprocess.Popen(
        ["docker", "run", "--rm", "-it", {IMAGE_REF!r}],
        stdin=slave, stdout=slave, stderr=slave, close_fds=True,
    )
    os.close(slave)
    buf = bytearray()
    prompt_deadline = time.monotonic() + 20
    while time.monotonic() < prompt_deadline:
        r, _, _ = select.select([master], [], [], 0.25)
        if r:
            chunk = os.read(master, 4096)
            if not chunk:
                break
            buf.extend(chunk)
            if b"$" in buf or b"#" in buf:
                break
        elif proc.poll() is not None:
            break
    cmd = b"alias ll && complete -p devpkg && echo PTY_CHECK_OK\\nexit\\n"
    os.write(master, cmd)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        r, _, _ = select.select([master], [], [], 0.5)
        if r:
            try:
                chunk = os.read(master, 4096)
                if not chunk:
                    break
                buf.extend(chunk)
            except OSError:
                break
        elif proc.poll() is not None:
            break
    os.close(master)
    rc = proc.wait(timeout=10)
    text = buf.decode("utf-8", "replace")
    assert rc == 0, (rc, text)
    assert "ls -alF" in text, text
    assert "complete -F _devpkg devpkg" in text, text
    assert "PTY_CHECK_OK" in text, text
    """
          machine.succeed(as_desktop("python3 -c " + q(pty_script)), timeout=60)

          # Detached sleep infinity + docker stop -t 5 handled by tini in < 2s.
          cname = "stop-check"
          machine.succeed(as_desktop(f"docker rm -f {cname} >/dev/null 2>&1 || true"))
          machine.succeed(as_desktop(f"docker run -d --name {cname} {IMAGE_REF} sleep infinity"), timeout=30)
          machine.wait_until_succeeds(
              as_desktop(
                  f"docker exec {cname} bash -euo pipefail -c "
                  + q(
                      'test "$LANG" = en_US.UTF-8 && '
                      'test -r "$LOCALE_ARCHIVE" && '
                      'test -r "$SSL_CERT_FILE" && '
                      'grep -q "BEGIN CERTIFICATE" "$SSL_CERT_FILE" && '
                      'fc-match "sans-serif:lang=zh-cn:charset=0x95e8" | grep -Fq "Noto Sans CJK SC" && '
                      'fc-match "emoji:charset=0x1f600" | grep -Fq "Noto Color Emoji"'
                  )
              ),
              timeout=30,
          )
          stop_elapsed_str = machine.succeed(
              as_desktop(
                  "python3 -c "
                  + q(
                      f"import subprocess, time; t0 = time.monotonic(); "
                      f"subprocess.run(['docker', 'stop', '-t', '5', {cname!r}], stdout=subprocess.DEVNULL, check=True); "
                      f"print(f'{{time.monotonic() - t0:.4f}}')"
                  )
              ),
              timeout=15,
          ).strip()
          elapsed = float(stop_elapsed_str.splitlines()[-1])
          exit_code = int(
              machine.succeed(
                  as_desktop(f"docker inspect -f '{{{{.State.ExitCode}}}}' {cname}")
              ).strip()
          )
          machine.succeed(as_desktop(f"docker rm -f {cname}"))
          assert elapsed < 2.0, f"docker stop took {elapsed:.2f}s (expected < 2.0s via tini)"
          assert exit_code in (0, 143), f"Unexpected exit code after SIGTERM: {exit_code}"

      with subtest("2. Verify metadata labels, cache-layout contract, toolchains, and nested cache mount ownership"):
          latest_meta = machine.succeed(
              as_desktop(
                  f"docker image inspect {IMAGE_REF} | jq -r '.[0].Config.Labels[\"devcontainer.metadata\"] // empty'"
              )
          ).strip()
          assert latest_meta != "", "Expected devcontainer.metadata label"

          label_layout_raw = machine.succeed(
              as_desktop(
                  f"docker image inspect {IMAGE_REF} | jq -r '.[0].Config.Labels[\"devcontainers.nix.cache-layout\"] // empty'"
              )
          ).strip()
          assert label_layout_raw != "", "Expected devcontainers.nix.cache-layout label"
          label_layout = json.loads(label_layout_raw)
          assert label_layout.get("version") == 1 and len(label_layout.get("mounts") or []) == 20, label_layout

          machine.succeed(as_desktop(f"docker run -d --name check-latest {IMAGE_REF} sleep infinity"), timeout=30)
          try:
              in_image_layout = json.loads(
                  machine.succeed(
                      as_desktop("docker exec check-latest cat /usr/share/devcontainer/cache-layout.json")
                  )
              )
              assert in_image_layout == label_layout, "In-image cache-layout.json differs from OCI label"

              machine.succeed(
                  as_desktop(
                      "docker exec check-latest bash -euo pipefail -c "
                      + q(
                          "! command -v gh && "
                          "gcc --version >/dev/null && "
                          "ccache --version >/dev/null && "
                          "cmake --version >/dev/null && "
                          "ninja --version >/dev/null && "
                          "go version >/dev/null && "
                          "gopls version >/dev/null && "
                          "rustc --version | grep -Fiq nightly && "
                          "cargo --version >/dev/null && "
                          "rust-analyzer --version >/dev/null && "
                          "python3 --version >/dev/null && "
                          "uv --version >/dev/null && "
                          "ruff --version >/dev/null && "
                          "node --version >/dev/null && "
                          "npm --version >/dev/null && "
                          "pnpm --version >/dev/null && "
                          "eslint --version >/dev/null && "
                          "nixd --version >/dev/null && "
                          "nixfmt --version >/dev/null && "
                          "shellcheck --version >/dev/null && "
                          "shfmt --version >/dev/null && "
                          "taplo --version >/dev/null && "
                          "protoc --version >/dev/null && "
                          "buf --version >/dev/null && "
                          "command -v wayland-info >/dev/null && "
                          "codex --version >/dev/null && "
                          "opencode --version >/dev/null && "
                          "agy --version >/dev/null && "
                          "vm-test-submit --version >/dev/null"
                      )
                  ),
                  timeout=120,
              )
              machine.succeed(
                  as_desktop(
                      f"docker cp {q(CONCURRENT_LIFECYCLE_PY)} check-latest:/tmp/check-concurrent-lifecycle.py && "
                      "docker exec check-latest python3 /tmp/check-concurrent-lifecycle.py"
                  ),
                  timeout=90,
              )
              machine.succeed(
                  "rm -rf /tmp/pnpm-ws /tmp/pnpm-store && mkdir -p /tmp/pnpm-ws /tmp/pnpm-store && chown 1000:1000 /tmp/pnpm-ws /tmp/pnpm-store"
              )
              pnpm_store = machine.succeed(
                  as_desktop(
                      f"docker run --rm "
                      f"-v /tmp/pnpm-ws:/workspaces/pnpm-ws "
                      f"-v /tmp/pnpm-store:/home/vscode/.cache/pnpm/store "
                      f"-w /workspaces/pnpm-ws {IMAGE_REF} bash -euo pipefail -c "
                      + q("touch /home/vscode/.cache/pnpm/metadata-probe && pnpm store path")
                  ),
                  timeout=60,
              ).strip()
              machine.succeed("rm -rf /tmp/pnpm-ws /tmp/pnpm-store")
              assert pnpm_store.startswith("/home/vscode/.cache/pnpm/store"), (
                  f"Expected pnpm store under /home/vscode/.cache/pnpm/store, got {pnpm_store!r}"
              )
          finally:
              machine.succeed(as_desktop("docker rm -f check-latest"))

      with subtest("3. Verify 100ms host local cache probes on 172.17.0.1:37515 and 172.17.0.1:37516"):
          probe_off = machine.succeed(
              as_desktop(
                  f"err_file=$(mktemp) && "
                  f"out=$(docker run --rm {IMAGE_REF} bash -euo pipefail -c "
                  + q(
                      "test ! -e /home/vscode/.local/state/devcontainer/nix-local-cache.conf && "
                      "nix config show substituters"
                  )
                  + " 2>\"$err_file\") && "
                  "err=$(cat \"$err_file\") && rm -f \"$err_file\" && "
                  "test -z \"$err\" && printf '%s\\n' \"$out\""
              ),
              timeout=60,
          )
          assert "172.17.0.1:37515" not in probe_off, f"Unexpected local cache when port closed: {probe_off!r}"
          assert "172.17.0.1:37516" not in probe_off, f"Unexpected host store cache when port closed: {probe_off!r}"

          machine.succeed(
              "rm -rf /tmp/mock-harmonia && mkdir -p /tmp/mock-harmonia && "
              "systemd-run --unit=mock-oranc-37515 "
              "python3 -m http.server 37515 --bind 172.17.0.1 && "
              "systemd-run --unit=mock-harmonia-37516 "
              "python3 -m http.server 37516 --bind 172.17.0.1 --directory /tmp/mock-harmonia"
          )
          try:
              machine.wait_until_succeeds("curl -fsS http://172.17.0.1:37515/ >/dev/null", timeout=15)
              machine.wait_until_succeeds("curl -fsS http://172.17.0.1:37516/ >/dev/null", timeout=15)
              probe_partial = machine.succeed(
                  as_desktop(
                      f"docker run --rm {IMAGE_REF} bash -euo pipefail -c "
                      + q(
                          "test -f /home/vscode/.local/state/devcontainer/nix-local-cache.conf && "
                          "nix config show substituters"
                      )
                  ),
                  timeout=60,
              )
              assert "http://172.17.0.1:37515/ghcr.io/hellodword/nixos-config-cache" in probe_partial, probe_partial
              assert "http://172.17.0.1:37515/ghcr.io/hellodword/devcontainers-nix-cache" in probe_partial, probe_partial
              assert "172.17.0.1:37516" not in probe_partial, f"Expected non-Nix 37516 HTTP server to be ignored: {probe_partial!r}"

              machine.succeed(
                  "printf 'StoreDir: /nix/store\\nWantMassQuery: 1\\nPriority: 30\\n' > /tmp/mock-harmonia/nix-cache-info"
              )
              probe_both = machine.succeed(
                  as_desktop(
                      f"docker run --rm {IMAGE_REF} bash -euo pipefail -c "
                      + q("nix config show substituters")
                  ),
                  timeout=60,
              )
              assert "http://172.17.0.1:37516" in probe_both, probe_both
          finally:
              machine.succeed("systemctl stop mock-oranc-37515.service mock-harmonia-37516.service && rm -rf /tmp/mock-harmonia")

      with subtest("4. Verify 6-line Dockerfile thin UID=1234 GID=1235 derivation"):
          index_data = json.loads(machine.succeed(f"cat {q(OCI_DIR)}/index.json"))
          latest_digest = index_data["manifests"][0]["digest"]
          helper_ver = machine.succeed(
              as_desktop(f"docker run --rm {IMAGE_REF} /usr/bin/devcontainer-set-user-id --version")
          ).strip()
          assert helper_ver == "devcontainer-set-user-id 1", f"Unexpected helper version: {helper_ver!r}"

          derived_key = hashlib.sha256(
              f"{latest_digest}:1234:1235:{helper_ver}".encode("utf-8")
          ).hexdigest()
          derived_tag = f"devcontainer-derived:{derived_key[:24]}"
          build_dir = "/tmp/derive-latest"
          dockerfile = (
              f"FROM {IMAGE_REF}\n"
              "USER root\n"
              "ARG DEV_UID=1000\n"
              "ARG DEV_GID=1000\n"
              'RUN /usr/bin/devcontainer-set-user-id --uid "$DEV_UID" --gid "$DEV_GID"\n'
              "ENV XDG_RUNTIME_DIR=/run/user/''${DEV_UID}\n"
              "USER vscode\n"
          )
          machine.succeed(
              f"rm -rf {build_dir} /tmp/work-derived && "
              f"mkdir -p {build_dir} /tmp/work-derived && "
              f"chown 1234:1235 /tmp/work-derived && "
              f"printf %s {q(dockerfile)} > {build_dir}/Dockerfile"
          )
          machine.succeed(
              as_desktop(
                  f"docker build -t {derived_tag} "
                  f"--build-arg DEV_UID=1234 --build-arg DEV_GID=1235 {build_dir}"
              ),
              timeout=300,
          )
          cname = "derived-latest"
          machine.succeed(
              as_desktop(
                  f"docker run -d --name {cname} -v /tmp/work-derived:/workspaces/work {derived_tag} sleep infinity"
              ),
              timeout=30,
          )
          try:
              machine.succeed(
                  as_desktop(
                      f"docker exec {cname} bash -euo pipefail -c "
                      + q(
                          'test "$(id -un)" = vscode && '
                          'test "$(id -u)" = 1234 && '
                          'test "$(id -g)" = 1235 && '
                          'test "$XDG_RUNTIME_DIR" = /run/user/1234 && '
                          'test "$(stat -c %a "$XDG_RUNTIME_DIR")" = 700 && '
                          'test "$(stat -c %u:%g /var/cache/devcontainer-nix)" = 1234:1235 && '
                          'echo owned-by-derived > /workspaces/work/probe.txt'
                      )
                  ),
                  timeout=30,
              )
              owner = machine.succeed("stat -c '%u:%g' /tmp/work-derived/probe.txt").strip()
              assert owner == "1234:1235", f"Expected 1234:1235 on host bind mount, got {owner!r}"
          finally:
              machine.succeed(as_desktop(f"docker rm -f {cname} && docker rmi {derived_tag}"))
              machine.succeed(f"rm -rf {build_dir} /tmp/work-derived")

      with subtest("5. Verify offline devpkg add/remove/add-lib/add-dev-lib in --network none"):
          machine.succeed(
              as_desktop(f"docker run -d --network none --name offline-devpkg {IMAGE_REF} sleep infinity"),
              timeout=30,
          )
          try:
              machine.succeed(
                  as_desktop(
                      "docker exec offline-devpkg bash -lc '! command -v patchelf >/dev/null 2>&1 && devpkg add patchelf'"
                  ),
                  timeout=120,
              )
              machine.succeed(
                  as_desktop("docker exec offline-devpkg bash -lc 'patchelf --version >/dev/null'"),
                  timeout=30,
              )
              machine.succeed(
                  as_desktop(
                      "docker exec offline-devpkg bash -lc 'devpkg remove patchelf && ! command -v patchelf >/dev/null 2>&1'"
                  ),
                  timeout=60,
              )

              machine.succeed(
                  as_desktop(
                      "docker exec offline-devpkg bash -euo pipefail -c "
                      + q(
                          "devpkg add-lib zlib && "
                          "devpkg add-dev-lib zlib && "
                          'test -e "$DEVPKG_RUNTIME_LIBRARY_PROFILE/lib/libz.so" && '
                          'test -f "$DEVPKG_BUILD_LIBRARY_PROFILE/include/zlib.h" && '
                          '(test -f "$DEVPKG_BUILD_LIBRARY_PROFILE/lib/pkgconfig/zlib.pc" || '
                          'test -f "$DEVPKG_BUILD_LIBRARY_PROFILE/share/pkgconfig/zlib.pc") && '
                          "devpkg list-lib --json | jq -e '.elements | length == 1' >/dev/null && "
                          "devpkg list-dev-lib --json | jq -e '.elements | length == 1' >/dev/null && "
                          "devpkg remove-lib zlib && "
                          "devpkg remove-dev-lib zlib"
                      )
                  ),
                  timeout=120,
              )
          finally:
              machine.succeed(as_desktop("docker rm -f offline-devpkg"))

      with subtest("6. Verify unprivileged offline Nix build, GC survival, and offline devShell zero-download reuse"):
          machine.succeed(
              as_desktop(f"docker run -d --network none --name offline-nix {IMAGE_REF} sleep infinity"),
              timeout=30,
          )
          try:
              gc_script = f"""
    set -euo pipefail
    ephemeral_out=$(nix build --offline --impure --option auto-optimise-store true --print-out-paths -o /tmp/ephemeral-link --expr '
      derivation {{
        name = "ephemeral-offline-check";
        system = "x86_64-linux";
        builder = "{EXPECTED_PATHS["bash"]}";
        args = [ "-c" "echo offline-built > $out" ];
      }}
    ')
    test "$(cat "$ephemeral_out")" = "offline-built"
    test "$(stat -c %h "$ephemeral_out")" -eq 2
    nix profile add "$ephemeral_out"
    nix profile list --json | jq -e '.elements | length == 1' >/dev/null
    nix profile remove ephemeral-offline-check
    nix profile wipe-history
    rm -f /tmp/ephemeral-link
    nix-store --gc >/tmp/gc.log
    if [ -e "$ephemeral_out" ]; then
      echo "Expected unreferenced ephemeral build $ephemeral_out to be collected by GC" >&2
      exit 1
    fi
    for preserved in \
      {q(EXPECTED_PATHS["nixpkgs"])} \
      {q(EXPECTED_PATHS["rustOverlay"])} \
      {q(EXPECTED_PATHS["rustToolchain"])} \
      {q(EXPECTED_PATHS["gcc"])} \
      {q(EXPECTED_PATHS["go"])} \
      {q(EXPECTED_PATHS["nodejs"])} \
      {q(EXPECTED_PATHS["python3"])} \
      {q(EXPECTED_PATHS["stdenv"])}; do
      test -e "$preserved"
      nix path-info "$preserved" >/dev/null
    done
    """
              machine.succeed(
                  as_desktop("docker exec offline-nix bash -c " + q(gc_script)),
                  timeout=900,
              )

              sample_flake = f"""{{
      inputs = {{
        nixpkgs.url = "path:{EXPECTED_PATHS['nixpkgs']}";
        rust-overlay = {{
          url = "path:{EXPECTED_PATHS['rustOverlay']}";
          inputs.nixpkgs.follows = "nixpkgs";
        }};
      }};
      outputs = {{ self, nixpkgs, rust-overlay }}:
        let
          pkgs = import nixpkgs {{
            system = "x86_64-linux";
            overlays = [ rust-overlay.overlays.default ];
          }};
          rustToolchain = pkgs.rust-bin.selectLatestNightlyWith (toolchain:
            toolchain.default.override {{
              extensions = [ "rust-src" "rustfmt" "clippy" "rust-analyzer" ];
            }}
          );
        in {{
          devShells.x86_64-linux.default = pkgs.mkShell {{
            packages = [
              rustToolchain
              pkgs.gcc
              (pkgs.go_latest or pkgs.go)
            ];
          }};
        }};
    }}
    """
              devshell_script = f"""
    set -euo pipefail
    mkdir -p /workspaces/sample-project/src /workspaces/sample-project/cmd
    printf '%s' {q(sample_flake)} > /workspaces/sample-project/flake.nix
    cat <<'EOF' > /workspaces/sample-project/Cargo.toml
    [package]
    name = "sample_rust"
    version = "0.1.0"
    edition = "2021"
    EOF
    cat <<'EOF' > /workspaces/sample-project/src/main.rs
    fn main() {{
        println!("RUST_OFFLINE_OK");
    }}
    EOF
    cat <<'EOF' > /workspaces/sample-project/hello.c
    #include <stdio.h>
    int main(void) {{
        puts("C_OFFLINE_OK");
        return 0;
    }}
    EOF
    cat <<'EOF' > /workspaces/sample-project/cmd/go.mod
    module example.com/offlinego
    go 1.22
    EOF
    cat <<'EOF' > /workspaces/sample-project/cmd/main.go
    package main
    import "fmt"
    func main() {{
        fmt.Println("GO_OFFLINE_OK")
    }}
    EOF

    cd /workspaces/sample-project
    nix flake lock --offline
    nix develop --offline --command bash -euo pipefail -c '
      actual_rustc="$(readlink -f "$(command -v rustc)")"
      actual_gcc="$(readlink -f "$(command -v gcc)")"
      actual_go="$(readlink -f "$(command -v go)")"
      case "$actual_rustc" in
        {q(EXPECTED_PATHS["rustToolchain"])}/*) ;;
        *) echo "Unexpected rustc path: $actual_rustc" >&2; exit 1 ;;
      esac
      case "$actual_gcc" in
        {q(EXPECTED_PATHS["gcc"])}/*) ;;
        *) echo "Unexpected gcc path: $actual_gcc" >&2; exit 1 ;;
      esac
      case "$actual_go" in
        {q(EXPECTED_PATHS["go"])}/*) ;;
        *) echo "Unexpected go path: $actual_go" >&2; exit 1 ;;
      esac

      cargo build --offline
      test "$(./target/debug/sample_rust)" = "RUST_OFFLINE_OK"

      gcc hello.c -o hello_c
      test "$(./hello_c)" = "C_OFFLINE_OK"

      (cd cmd && go build -o hello_go . && test "$(./hello_go)" = "GO_OFFLINE_OK")
    '
    """
              machine.succeed(
                  as_desktop("docker exec offline-nix bash -c " + q(devshell_script)),
                  timeout=300,
              )
          finally:
              machine.succeed(as_desktop("docker rm -f offline-nix"))

      with subtest("7. Verify gVisor (--runtime=runsc), shared Nix cache publish/substitute, and isolated prune-caches"):
          machine.succeed(
              as_desktop(
                  f"docker run --rm --runtime=runsc --network none {IMAGE_REF} bash -euo pipefail -c "
                  + q(
                      'test "$(id -un)" = vscode && '
                      'test "$(id -u)" = 1000 && '
                      'test -s /etc/machine-id && '
                      'codex --version >/dev/null && '
                      'opencode --version >/dev/null && '
                      'agy --version >/dev/null && '
                      'vm-test-submit --version >/dev/null'
                  )
              ),
              timeout=120,
          )

          runsc_nix_file = "\n".join(
              [
                  "{ idx }:",
                  "derivation {",
                  '  name = "runsc-nix-build-" + idx;',
                  '  system = "x86_64-linux";',
                  f'  builder = "{EXPECTED_PATHS["bash"]}";',
                  "  args = [",
                  '    "-c"',
                  r'    "[ -z \"$LD_PRELOAD\" ] && printf \"runsc-ok-%s\\n\" \"$1\" > \"$out\""',
                  '    "--"',
                  "    idx",
                  "  ];",
                  "}",
              ]
          )
          runsc_build_script = f"""
    set -euo pipefail
    printf '%s' {q(runsc_nix_file)} > /tmp/runsc-build.nix
    for idx in 1 2 3 4 5; do
      out=$(nix build --offline --impure --print-out-paths --no-link --file /tmp/runsc-build.nix --argstr idx "$idx")
      test "$(cat "$out")" = "runsc-ok-$idx"
    done
    """
          machine.succeed(
              as_desktop(
                  f"docker run --rm --runtime=runsc --network none {IMAGE_REF} bash -c "
                  + q(runsc_build_script)
              ),
              timeout=180,
          )

          shared_drv_expr = "\n".join(
              [
                  "derivation {",
                  '  name = "shared-cache-cross-runtime";',
                  '  system = "x86_64-linux";',
                  f'  builder = "{EXPECTED_PATHS["bash"]}";',
                  "  args = [",
                  '    "-c"',
                  f'    "printf \\"%s\\\\n\\" \\"{EXPECTED_PATHS["bash"]}-shared-ok\\" > \\"$out\\""',
                  "  ];",
                  "}",
              ]
          )
          shared_build_cmd = (
              "set -euo pipefail; "
              f"printf '%s' {q(shared_drv_expr)} > /tmp/shared-drv.nix; "
              "out=$(nix build --impure --no-substitute --print-out-paths --no-link --file /tmp/shared-drv.nix); "
              f'test "$(cat "$out")" = "{EXPECTED_PATHS["bash"]}-shared-ok"'
          )
          shared_subst_cmd = (
              "set -euo pipefail; "
              f"printf '%s' {q(shared_drv_expr)} > /tmp/shared-drv.nix; "
              "out=$(nix build --impure --substitute --max-jobs 0 --print-out-paths --no-link --file /tmp/shared-drv.nix); "
              f'test "$(cat "$out")" = "{EXPECTED_PATHS["bash"]}-shared-ok"'
          )
          machine.succeed(
              "rm -rf /tmp/shared-nix-cache /tmp/shared-gomod /tmp/host-sentinel && "
              "mkdir -p /tmp/shared-nix-cache /tmp/shared-gomod/example.com/v1 /tmp/host-sentinel && "
              "printf 'HOST_SECRET_INTACT\\n' > /tmp/host-sentinel/token && "
              "chmod 0600 /tmp/host-sentinel/token && "
              "dd if=/dev/zero of=/tmp/shared-gomod/example.com/v1/blob bs=1024 count=8 status=none && "
              "ln -s /tmp/host-sentinel/token /tmp/shared-gomod/example.com/v1/escape && "
              "chown -R 1000:1000 /tmp/shared-nix-cache /tmp/shared-gomod && "
              "chmod 0555 /tmp/shared-gomod/example.com/v1"
          )
          try:
              concurrent_writers = (
                  f"docker run --rm --network none -v /tmp/shared-nix-cache:/var/cache/devcontainer-nix {IMAGE_REF} bash -c {q(shared_build_cmd)} & "
                  "p1=$!; "
                  f"docker run --rm --runtime=runsc --network none -v /tmp/shared-nix-cache:/var/cache/devcontainer-nix {IMAGE_REF} bash -c {q(shared_build_cmd)} & "
                  "p2=$!; "
                  "wait $p1 && wait $p2"
              )
              machine.succeed(as_desktop(concurrent_writers), timeout=240)
              machine.succeed("compgen -G '/tmp/shared-nix-cache/*.narinfo' >/dev/null && compgen -G '/tmp/shared-nix-cache/nar/*.nar.zst' >/dev/null")

              machine.succeed(
                  as_desktop(
                      f"docker run --rm --network none -v /tmp/shared-nix-cache:/var/cache/devcontainer-nix:ro {IMAGE_REF} bash -c {q(shared_subst_cmd)}"
                  ),
                  timeout=120,
              )

              machine.succeed("touch -d '40 days ago' /tmp/shared-nix-cache/*.narinfo")
              prune_json = machine.succeed(
                  as_desktop(
                      f"docker run --rm --network none "
                      f"-v /tmp/shared-nix-cache:/var/cache/devcontainer-nix "
                      f"-v /tmp/shared-gomod:/home/vscode/.cache/go/pkg/mod "
                      f"{IMAGE_REF} devcontainer-runtime prune-caches "
                      f"--pool-max-bytes 1024 --idle"
                  ),
                  timeout=120,
              ).strip()
              prune_data = json.loads(prune_json)
              assert prune_data["pools"]["nix"]["removedNars"] >= 1, prune_data
              assert "go-mod" in prune_data["resetPools"], prune_data
              sentinel_text = machine.succeed("cat /tmp/host-sentinel/token").strip()
              assert sentinel_text == "HOST_SECRET_INTACT", sentinel_text
          finally:
              machine.succeed("chmod -R u+w /tmp/shared-gomod 2>/dev/null || true; rm -rf /tmp/shared-nix-cache /tmp/shared-gomod /tmp/host-sentinel")
  '';
})
