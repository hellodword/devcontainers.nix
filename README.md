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

More detail:

- [Architecture](docs/architecture.md)
- [Images](docs/images.md)
- [Remote Docker](docs/docker-remote.md)
- [Development](docs/development.md)
