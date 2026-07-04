# Usage

This guide is for project authors using the published images from
`.devcontainer/devcontainer.json`.

For the full image list, see [README: Quick Start](../README.md#quick-start).
For intent-based navigation, see [Documentation Index](index.md).

## Basic Devcontainer

Create `.devcontainer/devcontainer.json` with one published image reference:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-go:latest"
}
```

Pick another image tag from the README when the project needs a different
language or tool stack.

## Runtime Defaults

All images run as the fixed `vscode` user with uid/gid `1000`.

Do not set these fields in project `devcontainer.json`:

```json
{
  "remoteUser": "root",
  "containerUser": "root",
  "updateRemoteUserUID": true
}
```

The image metadata already sets `remoteUser`, `containerUser`, and
`updateRemoteUserUID` to the supported values. The image entrypoint refuses to
start as a different user, and `devcontainer-image check` reports these
overrides as invalid.

Important defaults:

- default working directory is `/workspaces`
- default shell is Bash
- default locale is `en_US.UTF-8`
- `/etc/localtime`, `/etc/zoneinfo`, and `TZDIR=/etc/zoneinfo` are present
- `fontconfig` and Noto Latin, CJK, symbol, and emoji fonts are installed
- Docker client tools are installed, but no Docker daemon is started inside the
  container; see [Remote Docker](docker-remote.md)
- Git, OpenSSH client tools, and nix-index are available in the base image set
- `LD_LIBRARY_PATH` is not exported by default

## VS Code Settings

Project-local VS Code settings belong in Dev Containers metadata:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "customizations": {
    "vscode": {
      "settings": {
        "nix.formatterPath": "nixfmt",
        "editor.formatOnSave": true
      }
    }
  }
}
```

These settings are applied by VS Code after it reads the image and project
metadata. Put repository-specific editor behavior here instead of baking it into
the published image.

## Packages

Use `devpkg` for project-specific tools that do not need to be baked into the
image.

Install packages after container creation:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "postCreateCommand": "devpkg add jq just"
}
```

Useful interactive commands:

```sh
devpkg search ripgrep
devpkg add ripgrep
devpkg list
devpkg remove ripgrep
```

Interactive Bash completion is available for `devpkg` commands, common options,
installed profile entries, and nixpkgs package attributes:

```sh
devpkg add div<TAB>
```

`devpkg` uses the image's locked nixpkgs input and nixpkgs policy, including
unfree package support and accepted Android SDK license gates. New containers do
not need to download nixpkgs before the first `devpkg add`.
Package-attribute completion caches nixpkgs attrnames in
`$XDG_CACHE_HOME/devpkg`, keyed by the image's locked nixpkgs input.

## Native Libraries And `LD_LIBRARY_PATH`

Runtime libraries are for programs that need shared objects at execution time:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-python3:latest",
  "postCreateCommand": "devpkg add-lib libGL"
}
```

Build libraries are for compiling and linking. They expose headers,
`pkg-config`, CMake prefixes, compiler wrapper flags, and runtime outputs:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-go:latest",
  "postCreateCommand": "devpkg add-dev-lib openssl zlib"
}
```

Select explicit package outputs when a project needs them:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-rust:latest",
  "postCreateCommand": "devpkg add-dev-lib --outputs out,dev,static zlib"
}
```

Go images enable the `cgo` library preset, so dynamically installed build
libraries also feed `CGO_CFLAGS` and `CGO_LDFLAGS`.

Rust and Flutter images enable the `rust-bindgen` preset, so build library
include paths feed `BINDGEN_EXTRA_CLANG_ARGS`. Projects that use bindgen still
need to install `clang` and `libclang` when their build requires those tools:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-rust:latest",
  "postCreateCommand": "devpkg add clang && devpkg add-dev-lib llvmPackages.libclang openssl"
}
```

If a non-Nix toolchain or FFI loader needs `LD_LIBRARY_PATH`, opt in explicitly:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-python3:latest",
  "postCreateCommand": "devpkg add-dev-lib openssl zlib",
  "remoteEnv": {
    "LD_LIBRARY_PATH": "/home/vscode/.local/share/devpkg/runtime-libraries/profile/lib:/home/vscode/.local/share/devpkg/build-libraries/profile/lib:${containerEnv:LD_LIBRARY_PATH}"
  }
}
```

Keep `LD_LIBRARY_PATH` scoped to the project because it changes dynamic loader
search order for every process that receives it.

## Environment Variables

Use `containerEnv` for values that should exist for the whole container, and
`remoteEnv` for VS Code and child processes started by VS Code.

Example with project-local Git, SSH, CA, and timezone settings:

```json
{
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

Do not bake proxy credentials, private keys, tokens, or machine-specific CA
bundles into an image. Use runtime environment, mounts, or local user
configuration for those values.

## Chromium And Browser Automation

Chromium-family browsers need container runtime settings that cannot be fixed
inside the image after startup.

Use a larger private `/dev/shm` for interactive browser work and browser
automation, and install Chromium plus any native build libraries the project
needs:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-nodejs:latest",
  "runArgs": ["--shm-size=1g"],
  "postCreateCommand": "devpkg add chromium && devpkg add-dev-lib openssl"
}
```

For Docker Compose based devcontainers:

```json
{
  "dockerComposeFile": "compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/app"
}
```

```yaml
services:
  dev:
    image: ghcr.io/hellodword/devcontainers-nodejs:latest
    shm_size: "1gb"
```

The images do not add `--no-sandbox`, do not install Chromium SUID sandbox
helpers, and do not relax container runtime security settings by default. See
[Chromium in Dev Containers](chromium.md) for browser behavior, `/dev/shm`
tradeoffs, sandbox failures, and the retained pitfall log.

## gVisor

gVisor is selected as the OCI runtime when the devcontainer is started. This is
independent from `DOCKER_HOST`; `DOCKER_HOST` only chooses which Docker daemon
the client talks to.

If the Docker daemon has `runsc` registered as a runtime, opt in from
`devcontainer.json`:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "runArgs": ["--runtime=runsc"]
}
```

For Docker Compose based devcontainers:

```json
{
  "dockerComposeFile": "compose.yaml",
  "service": "dev",
  "workspaceFolder": "/workspaces/app"
}
```

```yaml
services:
  dev:
    image: ghcr.io/hellodword/devcontainers-nix:latest
    runtime: runsc
```
