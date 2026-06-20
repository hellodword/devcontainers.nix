# devcontainers.nix

`devcontainers.nix` is an x86_64-linux first Nix compiler for VS Code Dev Container OCI images.

## Images

- `nix:latest`
- `go:latest`, `go:<major.minor>`, `go:web`
- `nodejs:latest`, `nodejs:<major>`
- `python:latest`, `python:<major.minor>`, `python:web`
- `rust:latest`, `rust:web`
- `flutter:latest`

All images run as `vscode` by default and include a VS Code-compatible FHS runtime.

## Quick Start

Load the Go image into Docker:

```sh
nix run .#load-go-latest
```

Example `.devcontainer/devcontainer.json`:

```json
{
  "name": "go",
  "image": "ghcr.io/hellodword/devcontainers-go:latest"
}
```

Remote Docker daemon example:

```json
{
  "name": "go",
  "image": "ghcr.io/hellodword/devcontainers-go:latest",
  "containerEnv": {
    "DOCKER_HOST": "tcp://172.17.0.1:2375"
  }
}
```

`tcp://172.17.0.1:2375` exposes a high-privilege Docker API. Use it only on trusted local or controlled hosts. Use a secure proxy or managed endpoint across machines.

Ad-hoc user package installs inside the container go through `devpkg`:

```sh
devpkg add cowsay
cowsay hello
devpkg list
devpkg remove cowsay
```

Native libraries use separate runtime and build profiles. Runtime libraries feed `NIX_LD_LIBRARY_PATH`; build libraries also expose headers, `pkg-config`, CMake, and compiler wrapper flags:

```sh
devpkg add-lib zlib
devpkg add-dev-lib openssl zlib
devpkg list-dev-lib
```

Images do not export `LD_LIBRARY_PATH` by default. Set `devcontainer.libraries.exportLdLibraryPath = true` in an image module, or add an explicit `remoteEnv.LD_LIBRARY_PATH` in a project `.devcontainer/devcontainer.json` when a non-Nix toolchain or FFI loader requires it.

More detail:

- [Architecture](docs/architecture.md)
- [Images](docs/images.md)
- [Remote Docker](docs/docker-remote.md)
- [Development](docs/development.md)
