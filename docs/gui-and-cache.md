# Wayland GUI Forwarding, Local Nix Cache Proxy, and Image Digests

## Native Wayland Forwarding (`:latest`)

`:latest` supports native Wayland client rendering against a host Wayland compositor (such as Sway) without X11 forwarding overhead.

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

Inspect active GUI forwarding inside `:latest`:

```bash
devcontainer-gui-env status
wayland-info
```

Set `DEVCONTAINER_GUI_ENV=0` to disable automatic GUI environment export, or `DEVCONTAINER_GUI_BACKEND=wayland|x11|auto` to select a specific backend.

## Host `oranc` Local Cache Auto-Discovery (`100ms` Probe)

`/etc/nix/nix.conf` configures single-user Nix with signature verification (`require-sigs = true`), sandbox fallback (`sandbox = true`, `sandbox-fallback = true`), public substituters (`cache.nixos.org`, `nix-community.cachix.org`, `cache.numtide.com`), and the two project signing public keys:

- `nixos-config-1:NfExPInFgDi/deX689T1M10hEORDGSZYRUapJMRbWM8=` (`ghcr.io/hellodword/nixos-config-cache`)
- `devcontainers-nix-1:Ypa0RlvJA7bRD/K3rdZLyiNMSt4AEgxACAUIrJZ5KD4=` (`ghcr.io/hellodword/devcontainers-nix-cache`)

It ends with an optional include directive:

```ini
!include /home/vscode/.local/state/devcontainer/nix-local-cache.conf
```

At container startup (`devcontainer-entrypoint`) and on `postStart` (`nix-cache-refresh` via `devcontainer-runtime refresh-local-cache`), the runtime performs a `100ms` TCP connection probe to `172.17.0.1:37515`:

- **Reachable**: Atomically writes `/home/vscode/.local/state/devcontainer/nix-local-cache.conf` adding `http://172.17.0.1:37515/ghcr.io/hellodword/nixos-config-cache` and `http://172.17.0.1:37515/ghcr.io/hellodword/devcontainers-nix-cache` as `extra-substituters` (`fallback = true`, `connect-timeout = 3`).
- **Unreachable / timeout**: Removes `nix-local-cache.conf` if present, resulting in zero Nix warnings and zero network wait when no host proxy is running.

Override behavior with environment variables when needed:

- `DEVCONTAINER_LOCAL_CACHE_PROBE=0` — disable probing and remove `nix-local-cache.conf`.
- `DEVCONTAINER_LOCAL_CACHE_ADDR=<host>:<port>` — probe a custom proxy endpoint.

### Host Client Cache Setup (`scripts/nix-cache.sh`)

Configure a host Nix client to trust and read the dual GHCR binary caches through a local `oranc` proxy (`172.17.0.1:37515`):

```bash
# Print configuration fragments
./scripts/nix-cache.sh print
./scripts/nix-cache.sh print --public-only
./scripts/nix-cache.sh print --ci

# Install managed block into ~/.config/nix/nix.conf
./scripts/nix-cache.sh install
```

## Shared OCI Layers and Digest Preservation

`nix build .#oci` writes both variants into a single OCI Image Layout directory:

1. **Layers 1–4 (shared across `:latest` and `:agent`)**:
   - Layer 1: Foundation utilities, FHS loader, locales, fonts, and `nix`
   - Layer 2: Five language toolchains, Nix language tools, formatters, `nixpkgs`, and `rust-overlay`
   - Layer 3: Open-source coding-agent CLIs (`codex`, `opencode`, `vm-test-submit`)
   - Layer 4: `antigravity-cli` (`agy`)
2. **Layers 5–6 (`:latest` only)**:
   - Layer 5: 25 open-source VS Code extensions and lifecycle task helpers
   - Layer 6: `ms-python.vscode-pylance`
3. **Top layer (per variant)**: `/usr`, `/etc`, user home skeleton, and initialized Nix SQLite database (`/nix/var/nix/db/db.sqlite` + `/nix/var/nix/gcroots/docker/`).

Release publication (`scripts/publish.py`) copies manifests with `skopeo copy --preserve-digests`, guaranteeing that `:sha-<commit>` and `:latest` share the exact byte-for-byte manifest digest produced during verification, and likewise for `:agent-sha-<commit>` and `:agent`.
