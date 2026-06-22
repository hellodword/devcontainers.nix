# devcontainers.nix

`devcontainers.nix` builds x86_64-linux VS Code Dev Container OCI images with Nix and nix2container.

The published images provide Nix, common development tools, VS Code-compatible runtime glue, preconfigured editor metadata, and the `devpkg` helper for adding packages inside a container.

## Motivation

I heavily rely on `Dev Containers` and `gVisor` in VS Code to set up development environments and isolate different projects.

`devcontainers.nix` uses Nix as the source of truth for packages, VS Code metadata, runtime environment variables, lifecycle tasks, semantic layer reports, and capability-driven smoke tests. `nixpkgs` provides a large package collection, binary caches, multi-architecture support, and a batteries-included development toolchain. `nix2container` turns that configuration into reproducible OCI images with inspectable layers and machine-readable reports.

Published images:

- `ghcr.io/hellodword/devcontainers-nix:latest`
- `ghcr.io/hellodword/devcontainers-go:latest`
- `ghcr.io/hellodword/devcontainers-go:1.26`
- `ghcr.io/hellodword/devcontainers-go:1.25`
- `ghcr.io/hellodword/devcontainers-go:web`
- `ghcr.io/hellodword/devcontainers-nodejs:latest`
- `ghcr.io/hellodword/devcontainers-nodejs:26`
- `ghcr.io/hellodword/devcontainers-nodejs:24`
- `ghcr.io/hellodword/devcontainers-python:latest`
- `ghcr.io/hellodword/devcontainers-python:3.13`
- `ghcr.io/hellodword/devcontainers-python:web`
- `ghcr.io/hellodword/devcontainers-rust:latest`
- `ghcr.io/hellodword/devcontainers-rust:web`
- `ghcr.io/hellodword/devcontainers-flutter:latest`

## Quick Start

Create `.devcontainer/devcontainer.json`:

```json
{
  "name": "go",
  "image": "ghcr.io/hellodword/devcontainers-go:latest"
}
```

Inside the container, add ad-hoc packages with `devpkg`:

```sh
devpkg add cowsay
cowsay hello
devpkg list
devpkg remove cowsay
```

## Documentation

- [Usage](docs/usage.md)
- [Architecture](docs/architecture.md)
- [Development and Maintenance](docs/development.md)
- [Fonts and Fontconfig](docs/fonts-fontconfig.md)
- [GUI Forwarding](docs/gui-forwarding.md)
- [Chromium in Dev Containers](docs/chromium.md)
