# devcontainers.nix

`devcontainers.nix` builds x86_64-linux VS Code Dev Container OCI images with Nix and nix2container.

The published images provide Nix, common development tools, VS Code-compatible runtime glue, preconfigured editor metadata, and the `devpkg` helper for adding packages inside a container.

## Motivation

I heavily rely on `Dev Containers` and `gVisor` in VS Code to set up development environments and isolate different projects.

The first version of this project used a base image plus Dev Container features. That worked, but most features were local shell scripts, so image builds were slow and the final behavior was hard to audit. The next version used the Dev Container CLI to build and publish prebuilt GHCR images. That improved startup time, but several problems remained: VS Code extensions and SDKs were still not fully captured, too much behavior lived in scripts, the image was difficult to layer deliberately, and nightly updates often made Docker pulls expensive.

After two years of that experience, the project was reworked around Nix. `nixpkgs` provides a large package collection, binary caches, multi-architecture support, and a batteries-included development toolchain. Nix can build reproducible Docker images, and the hash-based Nix store naturally avoids duplicating identical files. Tools like `dockerTools` and `nix2container` make it possible to organize reproducible, shareable layers so image pulls become closer to incremental updates.

This version keeps that motivation, but the exploration moved from hand-written feature scripts into a module-based image compiler. Packages, VS Code metadata, runtime environment variables, lifecycle tasks, semantic layer reports, and smoke tests are described as Nix configuration so the resulting images are easier to inspect and evolve without copying the old project architecture.

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
