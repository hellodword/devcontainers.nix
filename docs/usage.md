# Usage

This guide is for people using the published images from a project `.devcontainer/devcontainer.json`.

## Image References

The flake builds 11 image targets. Target names are used for local Nix outputs, generated workflow names, and smoke plans. Published image references use the `ghcr.io/hellodword/devcontainers-` prefix plus the target's family and tag.

| Target | Image reference | Use when |
| --- | --- | --- |
| `nix` | `ghcr.io/hellodword/devcontainers-nix:latest` | You work on Nix flakes, Nix modules, or general shell tooling. |
| `go` | `ghcr.io/hellodword/devcontainers-go:latest` | You want current Go plus common Go tools. |
| `go-1_25` | `ghcr.io/hellodword/devcontainers-go:1.25` | You need the previous Go major/minor line exposed by this repository. |
| `go-web` | `ghcr.io/hellodword/devcontainers-go:web` | You build Go services that also need web and data tools. |
| `nodejs` | `ghcr.io/hellodword/devcontainers-nodejs:latest` | You work on Node.js, TypeScript, frontend, or package-manager heavy projects. |
| `nodejs-24` | `ghcr.io/hellodword/devcontainers-nodejs:24` | You need the previous even Node.js major line exposed by this repository. |
| `python3` | `ghcr.io/hellodword/devcontainers-python:latest` | You work on Python projects with `uv`, `pipx`, formatters, linters, and test tools. |
| `python3-web` | `ghcr.io/hellodword/devcontainers-python:web` | You build Python services that also need web and data tools. |
| `rust` | `ghcr.io/hellodword/devcontainers-rust:latest` | You work on Rust projects with nightly Rust, rust-analyzer, clippy, and cargo helpers. |
| `rust-web` | `ghcr.io/hellodword/devcontainers-rust:web` | You build Rust services that also need web and data tools. |
| `flutter` | `ghcr.io/hellodword/devcontainers-flutter:latest` | You work on Flutter, Dart, Android, and Chromium-backed web workflows. |

`go`, `nodejs`, and `python3` also publish version tags for their current language line when the target defines one.

```shell
nix eval --json .#images \
    --apply 'images: builtins.mapAttrs (_: image: "${image.oci.imageName}:${image.oci.imageTag}") images' | jq -r 'to_entries[] | "\(.value)"'
```

## Basic Devcontainer

Minimal Go project:

```json
{
  "name": "go",
  "image": "ghcr.io/hellodword/devcontainers-go:latest"
}
```

Minimal Python project:

```json
{
  "name": "python",
  "image": "ghcr.io/hellodword/devcontainers-python:latest"
}
```

Minimal Node.js project:

```json
{
  "name": "nodejs",
  "image": "ghcr.io/hellodword/devcontainers-nodejs:latest"
}
```

Minimal Rust project:

```json
{
  "name": "rust",
  "image": "ghcr.io/hellodword/devcontainers-rust:latest"
}
```

Minimal Flutter project:

```json
{
  "name": "flutter",
  "image": "ghcr.io/hellodword/devcontainers-flutter:latest"
}
```

## Constraints

All images run as the fixed `vscode` user with uid/gid `1000`.

Do not set these fields in project `devcontainer.json`:

```json
{
  "remoteUser": "root",
  "containerUser": "root",
  "updateRemoteUserUID": true
}
```

The image metadata already sets `remoteUser`, `containerUser`, and `updateRemoteUserUID` to the supported values. The image entrypoint refuses to start as a different user, and `devcontainer-image check` reports these overrides as invalid.

Other important defaults:

- default working directory is `/workspaces`
- default shell is Bash
- default locale is `en_US.UTF-8`
- `/etc/localtime`, `/etc/zoneinfo`, and `TZDIR=/etc/zoneinfo` are present
- `fontconfig` and Noto Latin, CJK, symbol, and emoji fonts are installed
- Docker client tools are installed, but no Docker daemon is started inside the container
- Git, OpenSSH client tools, and nix-index are available in the base image set
- `LD_LIBRARY_PATH` is not exported by default

## Adding Packages

Use `devpkg` for project-specific tools that do not need to be baked into the image.

Install CLI packages after container creation:

```json
{
  "name": "nix-tools",
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "postCreateCommand": "devpkg add jq just"
}
```

Install browser packages from nixpkgs:

```json
{
  "name": "browser-test",
  "image": "ghcr.io/hellodword/devcontainers-nodejs:latest",
  "postCreateCommand": "devpkg add chromium"
}
```

`devpkg` uses the image's locked nixpkgs input and nixpkgs policy, including unfree package support and accepted Android SDK license gates. New containers do not need to download nixpkgs before the first `devpkg add`, and packages such as `google-chrome` and `microsoft-edge` evaluate the same way as image builds:

```json
{
  "name": "edge-test",
  "image": "ghcr.io/hellodword/devcontainers-nodejs:latest",
  "postCreateCommand": "devpkg add microsoft-edge"
}
```

Useful interactive commands:

```sh
devpkg search ripgrep
devpkg add ripgrep
devpkg list
devpkg remove ripgrep
```

Interactive Bash completion is available for `devpkg` commands, common options, installed profile entries, and nixpkgs package attributes:

```sh
devpkg add div<TAB>
```

## Adding Native Libraries

Runtime libraries are for programs that need shared objects at execution time:

```json
{
  "name": "ffi-runtime",
  "image": "ghcr.io/hellodword/devcontainers-python:latest",
  "postCreateCommand": "devpkg add-lib libGL"
}
```

Build libraries are for compiling and linking. They expose headers, `pkg-config`, CMake prefixes, compiler wrapper flags, and runtime outputs:

```json
{
  "name": "native-build",
  "image": "ghcr.io/hellodword/devcontainers-go:latest",
  "postCreateCommand": "devpkg add-dev-lib openssl zlib"
}
```

Select explicit package outputs when a project needs them:

```json
{
  "name": "static-zlib",
  "image": "ghcr.io/hellodword/devcontainers-rust:latest",
  "postCreateCommand": "devpkg add-dev-lib --outputs out,dev,static zlib"
}
```

Go images enable the `cgo` library preset, so dynamically installed build libraries also feed `CGO_CFLAGS` and `CGO_LDFLAGS`.

Rust and Flutter images enable the `rust-bindgen` preset, so build library include paths feed `BINDGEN_EXTRA_CLANG_ARGS`. Projects that use bindgen still need to install `clang` and `libclang` when their build requires those tools:

```json
{
  "name": "rust-bindgen",
  "image": "ghcr.io/hellodword/devcontainers-rust:latest",
  "postCreateCommand": "devpkg add clang && devpkg add-dev-lib llvmPackages.libclang openssl"
}
```

If a non-Nix toolchain or FFI loader needs `LD_LIBRARY_PATH`, opt in explicitly:

```json
{
  "name": "ffi",
  "image": "ghcr.io/hellodword/devcontainers-python:latest",
  "postCreateCommand": "devpkg add-dev-lib openssl zlib",
  "remoteEnv": {
    "LD_LIBRARY_PATH": "/home/vscode/.local/share/devpkg/runtime-libraries/profile/lib:/home/vscode/.local/share/devpkg/build-libraries/profile/lib:${containerEnv:LD_LIBRARY_PATH}"
  }
}
```

## Advanced Runtime Overrides

The image already includes system-level Git, SSH, CA, timezone, and nix-index support. Project-specific overrides should stay in `devcontainer.json` or mounted project files, not in a published image.

Example with project-local Git/SSH/CA/timezone settings:

```json
{
  "name": "advanced-runtime",
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "containerEnv": {
    "TZ": "America/New_York",
    "SSL_CERT_FILE": "/workspaces/${localWorkspaceFolderBasename}/.devcontainer/ca-bundle.pem",
    "NIX_SSL_CERT_FILE": "/workspaces/${localWorkspaceFolderBasename}/.devcontainer/ca-bundle.pem",
    "GIT_SSL_CAINFO": "/workspaces/${localWorkspaceFolderBasename}/.devcontainer/ca-bundle.pem",
    "GIT_SSH_COMMAND": "ssh -F /workspaces/${localWorkspaceFolderBasename}/.devcontainer/ssh_config"
  },
  "postCreateCommand": "git config --global include.path /workspaces/${localWorkspaceFolderBasename}/.devcontainer/gitconfig"
}
```

Do not bake proxy credentials, private keys, tokens, or machine-specific CA bundles into an image. Use runtime environment, mounts, or local user configuration for those values.

## Image Examples

Nix module or flake work:

```json
{
  "name": "nix",
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "customizations": {
    "vscode": {
      "settings": {
        "nix.formatterPath": "nixfmt"
      }
    }
  }
}
```

Go service with the web variant:

```json
{
  "name": "go-web",
  "image": "ghcr.io/hellodword/devcontainers-go:web",
  "postCreateCommand": "go version && node --version && devpkg add-dev-lib openssl"
}
```

Node.js project:

```json
{
  "name": "nodejs",
  "image": "ghcr.io/hellodword/devcontainers-nodejs:latest",
  "postCreateCommand": "pnpm install"
}
```

Python service with the web variant:

```json
{
  "name": "python3-web",
  "image": "ghcr.io/hellodword/devcontainers-python:web",
  "postCreateCommand": "uv sync"
}
```

Rust project:

```json
{
  "name": "rust",
  "image": "ghcr.io/hellodword/devcontainers-rust:latest",
  "postCreateCommand": "cargo fetch"
}
```

Flutter project:

```json
{
  "name": "flutter",
  "image": "ghcr.io/hellodword/devcontainers-flutter:latest",
  "runArgs": ["--shm-size=1g"],
  "postCreateCommand": "flutter pub get"
}
```

## Browser Configuration

Chromium-family browsers need container runtime settings that cannot be fixed inside the image after startup.

Use a larger private `/dev/shm` for interactive browser work and browser automation:

```json
{
  "name": "browser",
  "image": "ghcr.io/hellodword/devcontainers-flutter:latest",
  "runArgs": ["--shm-size=1g"]
}
```

For Docker Compose based devcontainers:

```json
{
  "name": "browser-compose",
  "dockerComposeFile": "compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/app"
}
```

```yaml
services:
  dev:
    image: ghcr.io/hellodword/devcontainers-flutter:latest
    shm_size: "1gb"
```

If VS Code provides Wayland forwarding but Chromium starts through X11, launch it with:

```sh
chromium --ozone-platform=wayland
```

The images do not add `--no-sandbox`, do not install Chromium SUID sandbox helpers, and do not relax container runtime security settings by default. See [Chromium in Dev Containers](chromium.md) for the detailed browser behavior and tradeoffs.
