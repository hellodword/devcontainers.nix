# devcontainers.nix

Modular Nix/OCI container images for interactive software development (`:latest`) and headless CLI / coding-agent execution (`:agent`), built from a shared `/nix/store` layer stack.

## Variants

| Capability                        | `ghcr.io/hellodword/devcontainers-dev:latest`                                                           | `ghcr.io/hellodword/devcontainers-dev:agent`                                                |
| --------------------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Primary role                      | Interactive development & VS Code Dev Containers                                                        | Headless CI, sandboxed tasks & coding-agent CLIs                                            |
| Default user & workdir            | `vscode` (`1000:1000`), `/workspaces`                                                                   | `vscode` (`1000:1000`), `/workspaces`                                                       |
| Entrypoint & supervisor           | `/usr/bin/devcontainer-entrypoint` (`tini -g`)                                                          | `/usr/bin/devcontainer-entrypoint` (`tini -g`)                                              |
| Shell, VCS, network & Nix CLI     | Included (`bash`, `git`, `ssh`, `gpg`, `jq`, `rg`, `fd`, `just`, `docker`, `nix`, `devpkg`)             | Included (`bash`, `git`, `ssh`, `gpg`, `jq`, `rg`, `fd`, `just`, `docker`, `nix`, `devpkg`) |
| Agent CLIs in `/usr/bin`          | `codex`, `opencode`, `agy`, `vm-test-submit`                                                            | `codex`, `opencode`, `agy`, `vm-test-submit`                                                |
| Language toolchains in `/usr/bin` | C/C++, Rust **Nightly**, Go, Python, Node.js/TypeScript, Nix LSP/formatters, Protobuf                   | Pre-populated in `/nix/store` with GC roots; omitted from `/usr/bin` and `PATH`             |
| Offline VS Code extensions        | 26 extensions + read-only `Machine/settings.json`                                                       | Not included                                                                                |
| `devcontainer.metadata` label     | Included (`init`, `overrideCommand`, `.devcontainer` read-only mount, `postCreate` / `postStart` tasks) | Omitted                                                                                     |
| Native Wayland diagnostics        | `devcontainer-gui-env` + `wayland-info`                                                                 | `devcontainer-gui-env`                                                                      |
| GitHub CLI (`gh`)                 | Omitted by design                                                                                       | Omitted by design                                                                           |

> **Rust toolchain channel**: `:latest` provides the **Rust Nightly** toolchain by default (`rustc`, `cargo`, `rust-src`, `rustfmt`, `clippy`, `rust-analyzer`, alongside `rustup`). Projects that target Rust Stable or a pinned compiler release declare a `rust-toolchain.toml` in the repository root or provide a pinned toolchain through a project `flake.nix` `devShell`; see [docs/packages-and-devshell.md](docs/packages-and-devshell.md).

## Quick Start

Minimal `.devcontainer/devcontainer.json` for standard `/workspaces/<repo>` projects with host UID/GID `1000:1000`:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest"
}
```

The image `devcontainer.metadata` label configures `remoteUser = "vscode"`, `init = true`, `overrideCommand = true`, read-only `.devcontainer` bind protection, offline VS Code extension projection (`postCreate`), and Wayland / local Nix cache refresh (`postStart`).

## Local Build, Load, and Verification

Build the deduplicated multi-variant OCI Image Layout (`index.json` containing both `latest` and `agent` manifests):

```bash
nix build .#oci
```

Load a variant directly into the local Docker daemon:

```bash
nix run .#load -- latest
nix run .#load -- agent
```

Run the full repository verification suite (formatting, static checks, OCI layout invariants, container runtime & `gVisor` workflows, offline VS Code + Sway Wayland session, and digest-preserving release tests):

```bash
nix run .#verify
```

## Image Tags and Digest Pinning

Published images under `ghcr.io/hellodword/devcontainers-dev` expose four tags sharing exact OCI manifest digests:

- `:latest` and `:sha-<40-char-commit>` — interactive development & Dev Container variant;
- `:agent` and `:agent-sha-<40-char-commit>` — headless CLI & coding-agent variant.

For reproducible builds and thin UID/GID derivations, pin by immutable commit tag or manifest digest:

```text
ghcr.io/hellodword/devcontainers-dev@sha256:<manifest-digest>
```

## Documentation

- [docs/usage.md](docs/usage.md) — Workspace layouts, `.devcontainer` read-only mounts, 6-line `Dockerfile` UID/GID derivation, and entrypoint account boundaries.
- [docs/packages-and-devshell.md](docs/packages-and-devshell.md) — Built-in toolchains, Rust Nightly & version pinning, `devpkg` package/library management, and offline `nix develop` store reuse in `:agent`.
- [docs/gui-and-cache.md](docs/gui-and-cache.md) — Native Wayland forwarding, `100ms` host `oranc` binary cache auto-discovery, client cache setup, and image digest semantics.
