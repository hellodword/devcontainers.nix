# devcontainers.nix

Modular Nix/OCI development container image (`ghcr.io/hellodword/devcontainers-dev:latest`) for VS Code Dev Containers, standalone `docker run` sessions, and coding-agent CLIs.

## Capabilities

| Aspect                            | Configuration                                                                                                                 |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Default user & workdir            | `vscode` (`1000:1000`), `/workspaces` (`01777`)                                                                               |
| Entrypoint & supervisor           | `/usr/bin/devcontainer-entrypoint` (`tini -g`)                                                                                |
| Shell, VCS, network & Nix CLI     | `bash`, `git`, `ssh`, `gpg`, `jq`, `rg`, `fd`, `just`, `docker`, `nix`, `devpkg`                                              |
| Agent CLIs in `/usr/bin`          | `codex`, `opencode`, `agy`, `vm-test-submit`                                                                                  |
| Language toolchains in `/usr/bin` | C/C++ (`gcc`, `ccache`, `cmake`, `ninja`), Rust **Nightly**, Go, Python, Node.js/TypeScript, Nix, Protobuf                    |
| Offline VS Code extensions        | 26 extensions + read-only `Machine/settings.json`                                                                             |
| `devcontainer.metadata` label     | `init`, `overrideCommand`, `.devcontainer` read-only mount, `postCreate` / `postStart` lifecycle tasks                        |
| Declarative cache contract        | `data/cache-layout.json`, `lib.cacheLayout`, `packages.x86_64-linux.cache-layout`, OCI label `devcontainers.nix.cache-layout` |
| Native Wayland forwarding         | `devcontainer-gui-env` + `wayland-info`                                                                                       |
| GitHub CLI (`gh`)                 | Omitted by design                                                                                                             |

> **Rust toolchain channel**: The image provides the **Rust Nightly** toolchain by default (`rustc`, `cargo`, `rust-src`, `rustfmt`, `clippy`, `rust-analyzer`, alongside `rustup`). Projects targeting Rust Stable or a pinned compiler release declare a `rust-toolchain.toml` in the repository root or provide a pinned toolchain through a project `flake.nix` `devShell`; see [docs/packages-and-devshell.md](docs/packages-and-devshell.md).

## Quick Start

Minimal `.devcontainer/devcontainer.json` for standard `/workspaces/<repo>` projects with host UID/GID `1000:1000`:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest"
}
```

The image `devcontainer.metadata` label configures `remoteUser = "vscode"`, `init = true`, `overrideCommand = true`, read-only `.devcontainer` bind protection, offline VS Code extension projection (`postCreate`), and Wayland / local Nix cache refresh (`postStart`).

## Local Build, Load, Cache Contract, and Verification

Build the OCI Image Layout (`index.json` containing the `latest` manifest):

```bash
nix build .#oci
```

Load the built image directly into the local Docker daemon:

```bash
nix run .#load
```

Query the declarative cache layout contract via Nix or OCI image metadata:

```bash
nix eval --json .#lib.cacheLayout
docker image inspect --format '{{ index .Config.Labels "devcontainers.nix.cache-layout" }}' ghcr.io/hellodword/devcontainers-dev:latest | jq .
```

Run the full repository verification suite (formatting, static checks, OCI layout invariants, container runtime & `gVisor` workflows, offline VS Code + Sway Wayland session, and digest-preserving release tests):

```bash
nix run .#verify
```

## Image Tags and Digest Pinning

Published releases under `ghcr.io/hellodword/devcontainers-dev` expose two tags sharing the exact OCI manifest digest:

- `:latest` — floating tag tracking `master`;
- `:sha-<40-char-commit>` — immutable commit-pinned tag.

For reproducible builds and thin UID/GID derivations, pin by immutable commit tag or manifest digest:

```text
ghcr.io/hellodword/devcontainers-dev@sha256:<manifest-digest>
```

## Documentation

- [docs/usage.md](docs/usage.md) — Workspace layouts, `.devcontainer` read-only mounts, 6-line `Dockerfile` UID/GID derivation, and entrypoint account boundaries.
- [docs/packages-and-devshell.md](docs/packages-and-devshell.md) — Built-in toolchains, Rust Nightly & version pinning, `devpkg` package/library management, and offline `nix develop` store reuse.
- [docs/gui-and-cache.md](docs/gui-and-cache.md) — Native Wayland forwarding, four-tier Nix cache auto-discovery (`file://`, host `harmonia`, and `oranc`), client cache setup, and OCI layer layout.
- [docs/security-and-sharing.md](docs/security-and-sharing.md) — Container-to-host threat model, standalone `docker run` hardening, declarative `cache-layout.json` pools, and scheduled idle cache reclamation.
