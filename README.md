# devcontainers.nix2

`devcontainers.nix2` is an x86_64-linux first Nix compiler for VS Code Dev Container OCI images.

## Images

- `nix:latest`
- `go:latest`, `go:<major.minor>`, `go:web`
- `nodejs:latest`, `nodejs:<major>`
- `python:latest`, `python:<major.minor>`, `python:web`
- `rust:latest`, `rust:web`
- `flutter:latest`

All images run as `vscode` by default and include a VS Code-compatible FHS runtime.

## Quick Start

Build reports:

```sh
nix build .#images.nix-latest.reports
```

Load the base image into Docker:

```sh
nix run .#load-nix-latest
```

Run a quick check:

```sh
docker run --rm ghcr.io/hellodword/devcontainers-nix:latest id vscode
docker run --rm ghcr.io/hellodword/devcontainers-nix:latest bash -lc 'test -e /lib64/ld-linux-x86-64.so.2 && test -e /usr/lib/libc.so.6'
```

## VS Code Dev Containers

Example `.devcontainer/devcontainer.json`:

```json
{
  "name": "nix",
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "remoteUser": "vscode",
  "containerUser": "vscode"
}
```

Remote Docker daemon example:

```json
{
  "name": "nix",
  "image": "ghcr.io/hellodword/devcontainers-nix:latest",
  "remoteUser": "vscode",
  "containerUser": "vscode",
  "containerEnv": {
    "DOCKER_HOST": "tcp://172.17.0.1:2375"
  }
}
```

`tcp://172.17.0.1:2375` exposes a high-privilege Docker API. Use it only on trusted local or controlled hosts. Use TLS or a secure proxy across machines.

More detail:

- [Architecture](docs/architecture.md)
- [Images](docs/images.md)
- [Remote Docker](docs/docker-remote.md)
- [Development](docs/development.md)
