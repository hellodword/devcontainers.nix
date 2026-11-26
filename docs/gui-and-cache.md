# Wayland GUI Forwarding, Multi-Tier Nix Caching, and Image Digests

## Native Wayland Forwarding

`ghcr.io/hellodword/devcontainers-dev:latest` supports native Wayland client rendering against a host Wayland compositor (such as Sway) without X11 forwarding overhead.

### Host Configuration

Enable Wayland socket forwarding in the host user's VS Code `settings.json`:

```json
{
  "dev.containers.mountWaylandSocket": true
}
```

For standalone `docker run` invocations on a host where `uid = 1000` runs a Wayland compositor at `/run/user/1000/wayland-1`, bind-mount the socket and pass `WAYLAND_DISPLAY`:

```bash
docker run --rm -it \
  -e WAYLAND_DISPLAY=wayland-1 \
  -v /run/user/1000/wayland-1:/run/user/1000/wayland-1 \
  ghcr.io/hellodword/devcontainers-dev:latest
```

### Container Discovery and Diagnostics

During container startup and the `postStart` task (`gui-env-refresh`), `devcontainer-gui-env refresh` scans `WAYLAND_DISPLAY`, `/run/user/<uid>`, `/tmp/user/<uid>`, and `/tmp` for valid Wayland sockets and writes `/run/user/<uid>/devcontainer-gui-env.sh` (`XDG_SESSION_TYPE=wayland`, `GDK_BACKEND=wayland,x11`, `QT_QPA_PLATFORM=wayland;xcb`, `SDL_VIDEODRIVER=wayland`, `MOZ_ENABLE_WAYLAND=1`, `NIXOS_OZONE_WL=1`). Interactive and login shells source this fragment automatically.

Inspect active GUI forwarding inside the container:

```bash
devcontainer-gui-env status
wayland-info
```

Set `DEVCONTAINER_GUI_ENV=0` to disable automatic GUI environment export, or `DEVCONTAINER_GUI_BACKEND=wayland|x11|auto` to select a specific backend.

---

## Four-Tier Nix Cache Architecture

`/etc/nix/nix.conf` configures single-user Nix with signature verification (`require-sigs = true`), sandbox fallback (`sandbox = true`, `sandbox-fallback = true`), public substituters (`cache.nixos.org`, `nix-community.cachix.org`, `cache.numtide.com`), and the two project signing public keys:

- `nixos-config-1:NfExPInFgDi/deX689T1M10hEORDGSZYRUapJMRbWM8=` (`ghcr.io/hellodword/nixos-config-cache`)
- `devcontainers-nix-1:Ypa0RlvJA7bRD/K3rdZLyiNMSt4AEgxACAUIrJZ5KD4=` (`ghcr.io/hellodword/devcontainers-nix-cache`)

It ends with an optional include directive:

```ini
!include /home/vscode/.local/state/devcontainer/nix-local-cache.conf
```

At container startup (`devcontainer-entrypoint`) and on `postStart` (`devcontainer-runtime refresh-local-cache`), the runtime composes up to four cache tiers without mounting or mutating the host's `/nix/store`:

1. **Tier 1 — Pre-baked image `/nix/store` layers (`OverlayFS` `lowerdir`)**: Shared across all running containers on the host with zero extra disk usage.
2. **Tier 2 — Mounted shared container build cache (`file:///var/cache/devcontainer-nix?trusted=1&priority=10`)**:
   - **Writable mount** (`-v ~/.local/state/devcontainers/cache/nix:/var/cache/devcontainer-nix`): Atomically initializes `nix-cache-info`, `nar/`, `realisations/`, `build-trace-v2/`, `log/`, and `.staging/`, adds the `file://` store at `priority=10`, and enables `post-build-hook` (`devcontainer-nix-post-build`). Locally built substitutable outputs stream through `nix store dump-path | zstd` into private `O_CREAT | O_EXCL` staging files and publish via `os.link` (`nar/` before `.narinfo`, first-writer-wins) without `flock` contention across `runc` or `gVisor` (`runsc`) containers.
   - **Read-only mount** (`:ro`): Enabled as a read-only substituter (`priority=10`, no `post-build-hook`) whenever `nix-cache-info`, `nar/`, `realisations/`, `build-trace-v2/`, and `log/` already exist. In `--network none` containers where Nix disables substitution when no external interface is present, pass `--substitute` (for example `nix build --substitute`) to read from the mounted `file://` cache; when no external interface or host HTTP cache is reachable, `nix-local-cache.conf` sets `substituters` to the local `file://` cache directly so unreachable public HTTPS caches are not queried.
3. **Tier 3 — Host `/nix/store` read-only HTTP exporter (`http://172.17.0.1:37516?trusted=1&priority=20`)**:
   - Performs a concurrent `100ms` HTTP `GET /nix-cache-info` probe to `172.17.0.1:37516` and activates the substituter only when the endpoint returns HTTP `200` with `StoreDir: /nix/store`.
   - Streams store paths already present on the host over loopback into the container's ephemeral `upperdir` (reclaimed automatically when `--rm` containers exit) while keeping the host store strictly read-only and avoiding VFS mount shadowing or live host SQLite `immutable=1` lock conflicts.
4. **Tier 4 — Host `oranc` OCI cache proxy (`172.17.0.1:37515`) & public signed caches**:
   - Concurrently probes `172.17.0.1:37515` within the same `100ms` budget; when reachable, appends `http://172.17.0.1:37515/ghcr.io/hellodword/{nixos-config-cache,devcontainers-nix-cache}` (`fallback = true`, `connect-timeout = 3`).

When no shared cache directory is mounted and neither host port is active, `nix-local-cache.conf` is removed so Nix emits zero warnings and incurs zero network wait.

### NixOS Host Read-Only Store Exporter (`services.harmonia.cache`)

Expose the NixOS host `/nix/store` read-only to local containers on `172.17.0.1:37516` using socket activation (zero idle memory, inaccessible from external interfaces):

```nix
{
  services.harmonia.cache = {
    enable = true;
    settings.bind = "172.17.0.1:37516";
  };
  systemd.sockets.harmonia.socketConfig.FreeBind = true;
}
```

> **Store readability**: Enabling `harmonia` allows containers reaching `172.17.0.1:37516` to read any path in the host `/nix/store`. Pass `-e DEVCONTAINER_HOST_STORE_CACHE_PROBE=0` when running containers that should not read host store paths.

### Cache Environment Controls

| Variable                                      | Default                       | Description                                                                      |
| --------------------------------------------- | ----------------------------- | -------------------------------------------------------------------------------- |
| `DEVCONTAINER_SHARED_NIX_CACHE`               | `auto`                        | `auto` (enable when mounted), `1` (enable if directory exists), or `0` (disable) |
| `DEVCONTAINER_SHARED_NIX_CACHE_DIR`           | `/var/cache/devcontainer-nix` | Shared `file://` binary cache path inside the container                          |
| `DEVCONTAINER_SHARED_NIX_CACHE_PUSH`          | `1`                           | Set `0` to disable `post-build-hook` writes on writable mounts                   |
| `DEVCONTAINER_SHARED_NIX_CACHE_MAX_NAR_BYTES` | `0`                           | Per-output `narSize` cap for auto-publishing (`0` = unlimited)                   |
| `DEVCONTAINER_NIX_CACHE_DEBUG`                | `0`                           | Set `1` to log `post-build-hook` diagnostics to `stderr`                         |
| `DEVCONTAINER_HOST_STORE_CACHE_PROBE`         | `1`                           | Probe host read-only store HTTP cache (`0` to disable)                           |
| `DEVCONTAINER_HOST_STORE_CACHE_ADDR`          | `172.17.0.1:37516`            | Host read-only store HTTP endpoint                                               |
| `DEVCONTAINER_LOCAL_CACHE_PROBE`              | `1`                           | Probe host `oranc` proxy (`0` disables network cache probes unless overridden)   |
| `DEVCONTAINER_LOCAL_CACHE_ADDR`               | `172.17.0.1:37515`            | Host `oranc` proxy endpoint                                                      |

### Cache Reclamation CLI (`devcontainer-runtime prune-caches`)

`devcontainer-runtime prune-caches` reads `/usr/share/devcontainer/cache-layout.json` inside an isolated `--rm --network none` container to reclaim expired and over-quota entries across all declared cache pools (see [docs/security-and-sharing.md](security-and-sharing.md)):

```bash
cache_root="$HOME/.local/state/devcontainers/cache"
mount_args=()
while IFS=$'\t' read -r id target mode; do
  install -d -m "$mode" "$cache_root/$id"
  mount_args+=(-v "$cache_root/$id:$target")
done < <(
  docker image inspect --format '{{ index .Config.Labels "devcontainers.nix.cache-layout" }}' \
    ghcr.io/hellodword/devcontainers-dev:latest \
    | jq -r '.mounts[] | [.id, .target, .mode] | @tsv'
)

docker run --rm --network none \
  "${mount_args[@]}" \
  ghcr.io/hellodword/devcontainers-dev:latest \
  devcontainer-runtime prune-caches --idle
```

Supported flags: `--cache-layout`, `--target-override ID=PATH`, `--max-age-days`, `--nix-max-bytes`, `--pool-max-bytes`, `--grace-seconds` (`600`), `--idle`, and `--dry-run`.

### Host Client Cache Setup (`nix run .#nix-cache`)

Configure a host Nix client to trust and read the dual GHCR binary caches through a local `oranc` proxy (`172.17.0.1:37515`):

```bash
# Print configuration fragments
nix run .#nix-cache -- print
nix run .#nix-cache -- print --public-only
nix run .#nix-cache -- print --ci

# Install managed block into ~/.config/nix/nix.conf
nix run .#nix-cache -- install
```

---

## OCI Layers and Digest Preservation

`nix build .#oci` produces a 7-layer OCI Image Layout directory (`index.json` targeting `latest`):

1. **Layer 1**: Foundation utilities, FHS loader, locales, fonts, and `nix`
2. **Layer 2**: Five language toolchains + `ccache`, Nix language tools, formatters, `nixpkgs`, and `rust-overlay`
3. **Layer 3**: Open-source coding-agent CLIs (`codex`, `opencode`, `vm-test-submit`)
4. **Layer 4**: `antigravity-cli` (`agy`)
5. **Layer 5**: 25 open-source VS Code extensions and lifecycle task helpers
6. **Layer 6**: `ms-python.vscode-pylance`
7. **Layer 7 (top layer)**: `/usr` (including `/usr/share/devcontainer/cache-layout.json`), `/etc`, pre-created `1000:1000` user/cache directories, `/workspaces` (`01777`), and initialized Nix SQLite database (`/nix/var/nix/db/db.sqlite` + `/nix/var/nix/gcroots/docker/`).

Release publication (`scripts/publish.py`) copies the manifest with `skopeo copy --preserve-digests`, guaranteeing that `:sha-<commit>` and `:latest` share the exact byte-for-byte manifest digest produced during verification.
