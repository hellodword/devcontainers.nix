# devcontainers.nix2

`devcontainers.nix2` is an x86_64-linux first Nix compiler for VS Code Dev Container OCI images.

## Images

- `nix`
- `python`
- `nodejs`
- `go`
- `rust`
- `python-web`
- `go-web`
- `rust-web`
- `flutter`

All images run as `vscode` by default and include Docker CLI tools, Codex CLI, and nix-index database tools.

## Quick Start

Build reports:

```sh
nix build .#images.nix.reports
```

Load the base image into Docker:

```sh
nix run .#load-nix
```

Run a quick check:

```sh
docker run --rm devcontainer-nix:latest id vscode
docker run --rm devcontainer-nix:latest bash -lc 'command -v docker && command -v codex && command -v nix-locate'
```

## VS Code Dev Containers

Example `.devcontainer/devcontainer.json`:

```json
{
  "name": "nix",
  "image": "devcontainer-nix:latest",
  "remoteUser": "vscode",
  "containerUser": "vscode"
}
```

Remote Docker daemon example:

```json
{
  "name": "nix",
  "image": "devcontainer-nix:latest",
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
