# Host Security Boundaries, Declarative Cache Contract, and Idle Reclamation

## Threat Model and Trust Boundaries

`devcontainers.nix` targets high-autonomy coding workflows where processes inside the container compile arbitrary project code, execute build scripts, install user-scoped packages, and run tests:

1. **Container interior is untrusted**: Standard unprivileged Docker containers run without nested user or mount namespaces. Coding-agent internal sandboxes and Nix build sandboxes (`sandbox-fallback = true`) do not isolate processes from other processes running as `vscode` (`1000:1000`) inside the same container.
2. **Shared writable mounts merge inter-container trust**: Mounting the same writable host directory into multiple containers places those containers in a shared trust domain for that resource.
3. **The host OS is the hard security boundary**: Compromised processes inside a container must not read unauthorized host files, invoke host control planes, or achieve **boomerang execution**—writing files into a mounted directory that a host process later parses, sources, or executes.

Evaluate every writable bind mount with a single question: **does any process running directly on the host parse, source, or execute files from this path?**

---

## Workspace Mounts, Standalone `docker run`, and Runtime Hardening

### Delayed Host Execution in Shared Workspaces

When bind-mounting a host Git checkout read-write (`-v "$PWD:/workspaces/${PWD##*/}"`), processes inside the container can modify repository metadata that host tools later evaluate:

- **Git configuration and hooks**: `.git/config` directives (`core.fsmonitor`, `core.sshCommand`, `diff.*.textconv`, `filter.*.clean`, `filter.*.smudge`) and `.git/hooks/*` execute commands as the host user when running `git status`, `git diff`, or `git commit` on the host.
- **Host environment loaders**: `.envrc` (`direnv`) and host-side shell hooks execute on the host if approved there.
- **`.devcontainer` lifecycle hooks**: Dev Container `initializeCommand` executes on the host. While `devcontainer.metadata` mounts `.devcontainer` read-only for Dev Container clients, standalone `docker run` ignores image metadata labels. Protect `.devcontainer` explicitly in `docker run` whenever present:

```bash
-v "$PWD/.devcontainer:/workspaces/${PWD##*/}/.devcontainer:ro"
```

For untrusted third-party repositories, use a dedicated container clone rather than sharing an active host checkout.

### Nested Read-Only Mount Stubs Inside a Workspace

In Linux VFS, bind-mounting a file or directory onto a target path requires an existing mountpoint inode at that target. Conditionally append workspace-level `:ro` mounts (such as `.devcontainer`, `AGENTS.md`, or `.agents`) in a launch wrapper only when the corresponding path already exists in `$PWD` so the Docker daemon never creates `root:root` stub files in the host working tree.

### Capability Sockets and Kernel Surface Reduction

- **Never mount raw host management sockets for routine development**: `/var/run/docker.sock` and `/nix/var/nix/daemon-socket/socket` are RPC capability endpoints; `:ro` on a Unix socket node does not restrict `connect()` RPCs.
- **Drop unused Linux capabilities and privilege escalation bits**: Because the image runs strictly as non-root `vscode` (`1000:1000`) with zero setuid binaries, standalone `docker run` sessions can add:
  ```bash
  --cap-drop=ALL --security-opt=no-new-privileges:true
  ```
- **Userspace kernel sandboxing (`gVisor`)**: The image supports `--runtime=runsc` (including single-user `nix build` and `nix develop` via the built-in PTY `EIO` retry shim) to reduce direct host kernel syscall exposure.

---

## Declarative Cache Contract (`data/cache-layout.json`)

Instead of bind-mounting the entire `/home/vscode/.cache` directory (which would mix cross-project bytecode/typecheck caches, executable shims, and single-container SQLite databases), `devcontainers.nix` publishes an explicit flat cache contract in [`data/cache-layout.json`](../data/cache-layout.json).

### Consuming the Contract

The identical JSON document is exposed across four surfaces so host launchers work both offline and online without duplicating paths:

1. **OCI image label (offline-first, version-locked to the local image)**:
   ```bash
   docker image inspect --format '{{ index .Config.Labels "devcontainers.nix.cache-layout" }}' \
     ghcr.io/hellodword/devcontainers-dev:latest
   ```
2. **In-image file**: `/usr/share/devcontainer/cache-layout.json` (read directly by `devcontainer-runtime prune-caches`).
3. **Flake outputs**: `lib.cacheLayout` (`nix eval --json .#lib.cacheLayout`) and `packages.x86_64-linux.cache-layout`.
4. **Git repository file**: `https://raw.githubusercontent.com/hellodword/devcontainers.nix/master/data/cache-layout.json`.

All target directories and their `/home/vscode/...` intermediate parent directories are pre-created in the image as `1000:1000`, preventing Docker from initializing missing parent paths as `root:root` when mounting individual cache subdirectories.

### Shared Cache Pools and Concurrency Boundaries

Each entry in `data/cache-layout.json` maps `~/.local/state/devcontainers/cache/<id>` on the host to `target` inside the container:

| Pool ID            | Container Path (`target`)              | Environment Variable                | Concurrency & Reclamation Notes                                                                                        |
| ------------------ | -------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `nix`              | `/var/cache/devcontainer-nix`          | `DEVCONTAINER_SHARED_NIX_CACHE_DIR` | Lock-free `O_EXCL` + `os.link` (`runc` & `runsc` safe); two-phase tombstone GC (`30d` / `32 GiB`, `600s` grace)        |
| `ccache`           | `/home/vscode/.cache/ccache`           | `CCACHE_DIR`                        | Atomic rename sharded CAS (`CCACHE_MAXSIZE=20G` self-managed LRU; `100 GiB` idle ceiling)                              |
| `cargo`            | `/home/vscode/.local/share/cargo`      | `CARGO_HOME`                        | Serialized via `.package-cache` `flock`; `--idle` sweeps `>30d` unpacked trees and trims `registry/cache > 20 GiB`     |
| `go-build`         | `/home/vscode/.cache/go-build`         | `GOCACHE`                           | `fcntl`-locked ActionID cache; Go self-trims `>5d` entries (`20 GiB` idle reset)                                       |
| `go-mod`           | `/home/vscode/.cache/go/pkg/mod`       | `GOMODCACHE`                        | Per-module `.lock` + `0555` trees; `--idle > 20 GiB` safely unlocks and clears                                         |
| `uv`               | `/home/vscode/.cache/uv`               | `UV_CACHE_DIR`                      | Multi-process safe (`UV_LINK_MODE=copy`); runs `uv cache prune --ci --no-config --offline` + `20 GiB` idle reset       |
| `pip`              | `/home/vscode/.cache/pip`              | `PIP_CACHE_DIR`                     | HTTP/wheel cache; `--idle` removes `>30d` files + `20 GiB` reset                                                       |
| `pnpm-store`       | `/home/vscode/.cache/pnpm/store`       | `PNPM_CONFIG_STORE_DIR`             | CAS (`PNPM_CONFIG_PACKAGE_IMPORT_METHOD=copy`); `20 GiB` idle reset (never run `pnpm store prune` in `copy` mode)      |
| `npm`              | `/home/vscode/.cache/npm`              | `NPM_CONFIG_CACHE`                  | `cacache` atomic writes; cleans `>30d` `_logs` online + `20 GiB` idle reset                                            |
| `yarn`             | `/home/vscode/.cache/yarn`             | `YARN_CACHE_FOLDER`                 | Archive cache; `20 GiB` idle reset                                                                                     |
| `node-gyp`         | `/home/vscode/.cache/node-gyp`         | _(native `$XDG_CACHE_HOME`)_        | Node/Electron C++ header tarballs; `--idle` cleans `>60d` files + `5 GiB` reset                                        |
| `pub`              | `/home/vscode/.cache/pub`              | `PUB_CACHE`                         | Dart / Flutter package cache; `20 GiB` idle reset                                                                      |
| `gradle`           | `/home/vscode/.cache/gradle`           | `GRADLE_USER_HOME`                  | Sequential container reuse safe; **do not run two Gradle builds simultaneously** across containers (`30 GiB` idle cap) |
| `electron`         | `/home/vscode/.cache/electron`         | `ELECTRON_CACHE`                    | `@electron/get` release zips; `--idle` cleans `>60d` files + `20 GiB` reset                                            |
| `electron-builder` | `/home/vscode/.cache/electron-builder` | `ELECTRON_BUILDER_CACHE`            | Packaging tool bundles; `--idle` cleans `>60d` files + `10 GiB` reset                                                  |
| `playwright`       | `/home/vscode/.cache/ms-playwright`    | _(native `$XDG_CACHE_HOME`)_        | Browser revisions; `--idle` cleans `>60d` files + `20 GiB` reset                                                       |
| `chromium-git`     | `/home/vscode/.cache/chromium-git`     | `GIT_CACHE_PATH`                    | `depot_tools` bare Git `.pack` mirrors; `manual` size reporting only (never auto-deletes individual pack files)        |
| `cipd`             | `/home/vscode/.cache/cipd`             | `CIPD_CACHE_DIR`                    | `depot_tools` CIPD CAS cache; `40 GiB` idle reset                                                                      |
| `vpython`          | `/home/vscode/.cache/vpython`          | `VPYTHON_VIRTUALENV_ROOT`           | `depot_tools` virtualenv cache; `vpython3` self-prunes + `10 GiB` idle reset                                           |
| `siso`             | `/home/vscode/.cache/siso`             | `SISO_CACHE_DIR`                    | Chromium Siso local CAS (`-local_cache_enable`); `--idle` cleans `>30d` files + `80 GiB` reset                         |

> **Filesystem snapshots and backups**: Exclude `~/.local/state/devcontainers/cache` from copy-on-write snapshots and backup jobs so evicted cache blocks are freed immediately.

### Advisory File Locks: `runc` vs `gVisor` (`runsc`)

Under `runc`, `flock(2)` and `fcntl` record locks operate on shared host kernel inodes and synchronize concurrent containers. Under `gVisor` (`--runtime=runsc`), advisory file locks remain local to each sandbox's Sentry kernel; mount language caches `:ro` when fanning out parallel `runsc` workers, while `/var/cache/devcontainer-nix` (`O_CREAT | O_EXCL` + `os.link`) remains race-free across concurrent `runc` and `runsc` writers.

---

## Coding-Agent Configuration Directories

Coding-agent CLIs store credentials, sessions, and configuration across:

- `codex`: `/home/vscode/.codex`
- `agy` / Gemini: `/home/vscode/.gemini`
- `opencode`: `/home/vscode/.config/opencode`, `/home/vscode/.local/share/opencode`, and `/home/vscode/.local/state/opencode`

Choose the host mapping that matches how coding agents are run on the host:

- **Shared host default paths** (`~/.codex`, `~/.gemini`, `~/.config/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`): Seamless authentication and session continuity between host and `--rm` containers when the host trusts the repositories opened in `devc`.
- **Container-dedicated directories** (`~/.local/state/devcontainers/{codex,gemini,opencode-...}`): Isolates container-modified agent hooks and MCP server definitions when coding agents are also executed directly on the host outside containers.

---

## Scheduled Idle-Time Cache Reclamation

Shared cache directories are writable by untrusted containers and may contain symlinks targeting host paths. **Never run host-side recursive deletion scripts or host package managers directly against container-writable cache directories.**

Run `devcontainer-runtime prune-caches` inside an unprivileged `docker run --rm --network none` container mounting only `~/.local/state/devcontainers/cache/<id>` pools. Inside that container, host home directories do not exist, and `prune-caches` uses `os.lstat` / `O_DIRECTORY | O_NOFOLLOW` throughout so symlinks are unlinked directly without `chmod` or directory traversal.

---

## Reference `docker run` Shell Function

```bash
devc() {
  local image="ghcr.io/hellodword/devcontainers-dev:latest"
  local workdir repo_name state_root layout_cache layout_json
  workdir="$(pwd -P)" || return 1
  repo_name="$(basename "$workdir")"
  state_root="${XDG_STATE_HOME:-$HOME/.local/state}/devcontainers"
  layout_cache="$state_root/cache-layout.json"

  layout_json="$(docker image inspect --format '{{ index .Config.Labels "devcontainers.nix.cache-layout" }}' "$image" 2>/dev/null || true)"
  if [[ -z "$layout_json" && -s "$layout_cache" ]]; then
    layout_json="$(<"$layout_cache")"
  elif [[ -z "$layout_json" ]]; then
    install -d -m 0700 "$state_root" || return 1
    layout_json="$(curl -fsSL https://raw.githubusercontent.com/hellodword/devcontainers.nix/master/data/cache-layout.json)" || return 1
    printf '%s\n' "$layout_json" >"$layout_cache"
  fi

  local -a ro_mounts=() cache_mounts=()
  local guard id target mode
  for guard in .devcontainer AGENTS.md .agents; do
    [[ -e "$workdir/$guard" ]] && ro_mounts+=(-v "$(realpath "$workdir/$guard"):/workspaces/$repo_name/$guard:ro")
  done

  for dir in \
    "$HOME/.codex" \
    "$HOME/.gemini" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/opencode" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/opencode" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/opencode" \
    "$state_root/cache"; do
    [[ -d "$dir" ]] || install -d -m 0700 "$dir" || return 1
  done

  while IFS=$'\t' read -r id target mode; do
    [[ -d "$state_root/cache/$id" ]] || install -d -m "$mode" "$state_root/cache/$id" || return 1
    cache_mounts+=(-v "$state_root/cache/$id:$target")
  done < <(printf '%s\n' "$layout_json" | jq -er '.mounts[] | [.id, .target, .mode] | @tsv')

  docker run --rm -it --init \
    --name "${repo_name}-$(od -vAn -N4 -tx1 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]')" \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    -v "$workdir:/workspaces/$repo_name" \
    "${ro_mounts[@]}" \
    -v "$HOME/.codex:/home/vscode/.codex" \
    -v "$HOME/.gemini:/home/vscode/.gemini" \
    -v "${XDG_CONFIG_HOME:-$HOME/.config}/opencode:/home/vscode/.config/opencode" \
    -v "${XDG_DATA_HOME:-$HOME/.local/share}/opencode:/home/vscode/.local/share/opencode" \
    -v "${XDG_STATE_HOME:-$HOME/.local/state}/opencode:/home/vscode/.local/state/opencode" \
    "${cache_mounts[@]}" \
    -w "/workspaces/$repo_name" \
    "$image" \
    "$@"
}
```
