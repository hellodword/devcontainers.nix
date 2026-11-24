# Host Security Boundaries, Cache Sharing, and Idle Reclamation

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
- **`.devcontainer` lifecycle hooks**: Dev Container `initializeCommand` executes on the host. While `:latest` embeds a read-only `.devcontainer` mount in `devcontainer.metadata` for Dev Container clients, standalone `docker run` ignores image metadata labels. Protect `.devcontainer` explicitly in `docker run` whenever present (and keep scripts referenced by `initializeCommand` outside writable workspace paths):

```bash
-v "$PWD/.devcontainer:/workspaces/${PWD##*/}/.devcontainer:ro"
```

For untrusted third-party repositories, use a dedicated container clone rather than sharing an active host checkout.

### Nested Read-Only Mount Stubs Inside a Workspace

In Linux VFS, bind-mounting a file or directory onto a target path requires an existing mountpoint inode at that target. When mounting read-only shared rules inside a read-write host workspace mount (for example `-v "$PWD:/workspaces/repo"` combined with `-v /path/to/AGENTS.md:/workspaces/repo/AGENTS.md:ro` and `-v /path/to/.agents:/workspaces/repo/.agents:ro`), if `AGENTS.md` or `.agents/` does not already exist in `$PWD`, the host Docker daemon (`root`) creates empty `root:root` file and directory stubs directly in the host working tree that persist after `--rm` container exit.

Avoid host working-tree stubs with either pattern:

- Mount shared agent instructions into user-scoped agent configuration directories (`~/.codex/AGENTS.md`, `~/.gemini/...`) rather than inside `/workspaces/<repo>`; or
- Conditionally append workspace-level `:ro` mounts in a launch wrapper only when the corresponding path already exists in `$PWD`.

### Capability Sockets and Kernel Surface Reduction

- **Never mount raw host management sockets for routine development**: `/var/run/docker.sock` and `/nix/var/nix/daemon-socket/socket` are RPC capability endpoints. Adding `:ro` to a Unix domain socket bind mount only blocks `unlink`/`chmod` on the socket node itself; `connect()` and daemon RPCs remain unrestricted.
- **Drop unused Linux capabilities and privilege escalation bits**: Because both variants run strictly as non-root `vscode` (`1000:1000`) with zero setuid binaries, standalone `docker run` sessions can add:
  ```bash
  --cap-drop=ALL --security-opt=no-new-privileges:true
  ```
- **Userspace kernel sandboxing (`gVisor`)**: Both `:latest` and `:agent` support `--runtime=runsc` (including single-user `nix build` and `nix develop` via the built-in PTY `EIO` retry shim) to reduce direct host kernel syscall exposure.

---

## Host Directory Layout (`~/.local/state/devcontainers`)

Store all container-shared state and caches under a dedicated host tree that host-native CLIs and compilers never read:

```text
~/.local/state/devcontainers/
├── codex/          # Container-dedicated CODEX_HOME (/home/vscode/.codex)
├── gemini/         # Container-dedicated Gemini/AGY state (/home/vscode/.gemini)
├── opencode/       # Container-dedicated OpenCode config/state (/home/vscode/.config/opencode)
└── cache/
    ├── nix/        # Shared file:// Nix binary cache (/var/cache/devcontainer-nix)
    ├── xdg/        # Shared XDG_CACHE_HOME (/home/vscode/.cache)
    └── cargo/      # Shared CARGO_HOME (/home/vscode/.local/share/cargo)
```

Pre-create directories as the host user (`mkdir -p`) before `docker run` so the Docker daemon never initializes missing host paths as `root:root`.

> **Filesystem snapshots and backups**: If `$HOME` uses copy-on-write filesystem snapshots (such as Btrfs or ZFS) or scheduled backup software, exclude `~/.local/state/devcontainers/cache` from snapshots and backups (for example via an exclusion rule or a dedicated subvolume/dataset) so evicted cache blocks are freed immediately.

---

## Language Cache Sharing and Concurrency Boundaries

### Unified Environment Across `:latest` and `:agent`

Both `:latest` and `:agent` export identical XDG and package-manager cache paths (while `:agent` keeps `/usr/bin` and `PATH` free of language compilers until entering `nix develop`):

| Ecosystem      | Environment Variables                                                                                                       | Container Path                                                   | Share Scope & Notes                                                                                                  |
| -------------- | --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Go             | `GOMODCACHE`, `GOCACHE`, `GOPATH`                                                                                           | `/home/vscode/.cache/go/pkg/mod`, `/home/vscode/.cache/go-build` | Covered by `/home/vscode/.cache`; `GOCACHE` self-trims daily                                                         |
| Python & `uv`  | `UV_CACHE_DIR`, `UV_LINK_MODE=copy`, `PIP_CACHE_DIR`, `MYPY_CACHE_DIR`, `PYTHONPYCACHEPREFIX`                               | `/home/vscode/.cache/{uv,pip,mypy,python}`                       | Covered by `/home/vscode/.cache`; `UV_LINK_MODE=copy` avoids cross-mount hardlink `EXDEV`                            |
| Node.js        | `NPM_CONFIG_CACHE`, `PNPM_CONFIG_STORE_DIR`, `PNPM_CONFIG_PACKAGE_IMPORT_METHOD=copy`, `YARN_CACHE_FOLDER`, `COREPACK_HOME` | `/home/vscode/.cache/{npm,pnpm/store,yarn,corepack}`             | Covered by `/home/vscode/.cache`; keeps `.pnpm-store` out of bind-mounted workspace `node_modules/`                  |
| `devpkg`       | `DEVPKG_CACHE_HOME` (default `$XDG_CACHE_HOME/devpkg`)                                                                      | `/home/vscode/.cache/devpkg`                                     | Covered by `/home/vscode/.cache`                                                                                     |
| Rust (`cargo`) | `CARGO_HOME`, `RUSTUP_HOME`                                                                                                 | `/home/vscode/.local/share/cargo`                                | Mount container-dedicated `cache/cargo` (or `registry` + `git` subdirs when isolating `credentials.toml` and `bin/`) |

Mounting two host directories covers all language caches above:

1. `-v "$HOME/.local/state/devcontainers/cache/xdg:/home/vscode/.cache"`
2. `-v "$HOME/.local/state/devcontainers/cache/cargo:/home/vscode/.local/share/cargo"`

### Advisory File Locks: `runc` vs `gVisor` (`runsc`)

- **Cargo `.package-cache` lock placement**: Cargo serializes concurrent crate extractions via `$CARGO_HOME/.package-cache`. Mounting a container-dedicated `CARGO_HOME` shares that lock inode across containers; mounting only `cargo/registry` and `cargo/git` isolates `credentials.toml` and `bin/` at the cost of per-container `.package-cache` locks.
- **`runc` vs `gVisor` (`--runtime=runsc`)**: Under `runc`, `flock(2)` and `fcntl` record locks operate on the shared host kernel inode and synchronize concurrent containers. Under `gVisor` (`runsc`), advisory file locks are managed inside each sandbox's userspace Sentry kernel memory and are not forwarded across separate `runsc` containers. Avoid concurrent writable Cargo/`uv` builds against the same language cache across parallel `runsc` containers (mount language caches `:ro` when fanning out parallel `runsc` workers). By contrast, `/var/cache/devcontainer-nix` uses lock-free `O_CREAT | O_EXCL` staging plus `os.link` publication and remains race-free across concurrent `runc` and `runsc` writers.

---

## Agent State and Shared Authentication

Agent home directories (`~/.codex`, `~/.gemini`, `~/.config/opencode`) store both authentication credentials and executable client settings (`mcp_servers` commands, hooks, plugins). Select one of two persistence patterns depending on whether workspace sessions should share history:

### Pattern 1: Container-Dedicated Shared Agent Directories (Minimal Friction)

When running `codex`, `agy`, or `opencode` inside ephemeral `--rm` containers, mount `~/.local/state/devcontainers/{codex,gemini,opencode}` rather than the host's own `$HOME/.{codex,gemini}`:

- Host CLI invocations never load container-modified MCP server commands or hooks, eliminating host boomerang execution.
- All `--rm` containers share authentication tokens, token refreshes, and session history without re-authentication.

### Pattern 2: Per-Workspace State with a Shared Authentication Directory

When isolating session transcripts and per-project agent config across workspaces or Git worktrees:

1. Compute a collision-resistant workspace key combining directory basename and canonical path digest:
   ```bash
   ws_id="$(basename "$PWD")-$(printf '%s' "$(pwd -P)" | sha256sum | cut -c1-8)"
   ws_codex="$HOME/.local/state/devcontainers/workspaces/$ws_id/codex"
   shared_auth="$HOME/.local/state/devcontainers/auth/codex"
   mkdir -p "$ws_codex" "$shared_auth"
   ```
2. Mount only that workspace's directory (`-v "$ws_codex:/home/vscode/.codex"`) alongside the dedicated shared authentication directory (for example `-v "$shared_auth:/home/vscode/.local/state/codex-auth"` paired with a directory-backed symlink or tool-supported auth store configuration), rather than bind-mounting a single `auth.json` file directly. Single-file bind mounts break atomic temp-file `rename()` token refreshes and separate sibling lockfiles (`auth.lock`).

---

## Scheduled Idle-Time Cache Reclamation

### Container-Isolated Execution Principle

Shared cache directories are writable by untrusted containers and may contain symlinks targeting host paths (such as `/home/<user>/.ssh`) or crafted tool config files. **Never run host-side recursive deletion scripts or host package managers directly against container-writable cache directories.**

Run `devcontainer-runtime prune-caches` inside an unprivileged `docker run --rm --network none` `:agent` container that mounts **only** `~/.local/state/devcontainers/cache`. Inside that container, host home directories do not exist, and `prune-caches` uses `os.lstat` / `O_DIRECTORY | O_NOFOLLOW` throughout so symlinks are unlinked directly without `chmod` or directory traversal.

### Reclamation Semantics and Tool Caveats

- **Shared Nix cache (`--nix-cache-dir`)**: Uses two-phase tombstone reclamation. Expired (`--max-age-days`, default `30`) and over-quota (`--nix-max-bytes`, default `32 GiB`, trimmed to an `80%` low watermark oldest-first) `.narinfo` files move to `.staging/gc-*.narinfo` tombstones. Online mode retains NARs referenced by tombstones or created within `--grace-seconds` (`600s`) so in-flight readers never hit `ENOENT`; `--idle` mode sweeps unreferenced `nar/*.nar.zst` files immediately.
- **Cargo (`--cargo-home`, `--idle` only)**: Removes whole expired unpacked directories under `registry/src/*/<crate>` and `git/checkouts/*/<rev>` (preserving `.cargo-ok` invariants and retaining `.crate` / `git/db` archives for offline re-extraction), and trims oldest `.crate` archives to `80%` when `registry/cache` exceeds `--lang-archive-max-bytes` (default `20 GiB`).
- **Python & `uv`**: Runs `uv cache prune --ci --no-config --offline` to drop unzipped wheel trees while keeping `.whl` archives, and prunes expired `python` / `mypy` cache files.
- **Download archive pools (`GOMODCACHE`, `pnpm/store`, `npm`, `yarn`, `pip`, `corepack`)**:
  - Do **not** run `pnpm store prune` against shared `copy`-mode stores: because `--rm` containers copy files rather than hardlinking (`st_nlink == 1`), `pnpm store prune` treats the entire store as unreferenced and deletes every package.
  - Do **not** run raw `find -mtime -delete` inside Nix `nar/`, Cargo `registry/src`, or read-only `0555` `GOMODCACHE` trees.
  - In `--idle` mode, `prune-caches` resets an individual archive pool only when its size exceeds `--lang-archive-max-bytes`.

### NixOS `systemd.user` Idle Prune Timer

Add a user timer on the NixOS host that checks whether any active container mounts the shared cache root, running deep `--idle` reclamation when idle and online tombstone reclamation otherwise:

```nix
{ pkgs, ... }:
let
  pruneScript = pkgs.writeShellApplication {
    name = "devcontainer-cache-prune";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.docker-client
      pkgs.jq
    ];
    text = ''
      cache_root="$HOME/.local/state/devcontainers/cache"
      [ -d "$cache_root" ] || exit 0
      mkdir -p "$cache_root/nix" "$cache_root/xdg" "$cache_root/cargo"

      idle_flag="--idle"
      ids="$(docker ps -q)"
      if [ -n "$ids" ]; then
        # shellcheck disable=SC2086
        if docker inspect $ids | jq -e --arg root "$cache_root" '
          any(.[]; any(.Mounts[]?; (.Source == $root) or (.Source | startswith($root + "/"))))
        ' >/dev/null; then
          idle_flag=""
        fi
      fi

      exec docker run --rm --network none \
        --cap-drop=ALL \
        --security-opt=no-new-privileges:true \
        -v "$cache_root/nix:/var/cache/devcontainer-nix" \
        -v "$cache_root/xdg:/home/vscode/.cache" \
        -v "$cache_root/cargo:/home/vscode/.local/share/cargo" \
        ghcr.io/hellodword/devcontainers-dev:agent \
        devcontainer-runtime prune-caches \
          --nix-cache-dir /var/cache/devcontainer-nix \
          --xdg-cache-dir /home/vscode/.cache \
          --cargo-home /home/vscode/.local/share/cargo \
          ''${idle_flag:+"$idle_flag"}
    '';
  };
in
{
  systemd.user.services.devcontainer-cache-prune = {
    Unit.Description = "Prune shared devcontainers.nix caches inside an isolated container";
    Service = {
      Type = "oneshot";
      ExecStart = "${pruneScript}/bin/devcontainer-cache-prune";
    };
  };

  systemd.user.timers.devcontainer-cache-prune = {
    Unit.Description = "Daily idle-aware shared cache reclamation for devcontainers.nix";
    Timer = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
```

---

## Reference `docker run` Shell Function

```bash
devc() {
  local repo_name="${PWD##*/}"
  local state_root="$HOME/.local/state/devcontainers"
  local rules_root="$HOME/dev/workspace/agents-misc"
  local -a extra_mounts=()

  mkdir -p \
    "$state_root/codex" \
    "$state_root/gemini" \
    "$state_root/opencode" \
    "$state_root/cache/nix" \
    "$state_root/cache/xdg" \
    "$state_root/cache/cargo"

  if [ -d "$PWD/.devcontainer" ]; then
    extra_mounts+=(-v "$PWD/.devcontainer:/workspaces/${repo_name}/.devcontainer:ro")
  fi
  if [ -e "$PWD/AGENTS.md" ] && [ -f "$rules_root/AGENTS.md" ]; then
    extra_mounts+=(-v "$rules_root/AGENTS.md:/workspaces/${repo_name}/AGENTS.md:ro")
  fi
  if [ -d "$PWD/.agents" ] && [ -d "$rules_root/.agents" ]; then
    extra_mounts+=(-v "$rules_root/.agents:/workspaces/${repo_name}/.agents:ro")
  fi

  docker run --cpus 4 --rm -it \
    --name "${repo_name}-$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')" \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    -v "$PWD:/workspaces/${repo_name}" \
    -v "$state_root/codex:/home/vscode/.codex" \
    -v "$state_root/gemini:/home/vscode/.gemini" \
    -v "$state_root/opencode:/home/vscode/.config/opencode" \
    -v "$state_root/cache/nix:/var/cache/devcontainer-nix" \
    -v "$state_root/cache/xdg:/home/vscode/.cache" \
    -v "$state_root/cache/cargo:/home/vscode/.local/share/cargo" \
    "${extra_mounts[@]}" \
    -w "/workspaces/${repo_name}" \
    ghcr.io/hellodword/devcontainers-dev:latest \
    "${@:-bash}"
}
```
