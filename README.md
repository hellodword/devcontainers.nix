# devcontainers.nix

`devcontainers.nix` is an x86_64-linux first Nix compiler for VS Code Dev Container OCI images.

## Images

- `nix:latest`
- `go:latest`, `go:<major.minor>`, `go:web`
- `nodejs:latest`, `nodejs:<major>`
- `python:latest`, `python:<major.minor>`, `python:web`
- `rust:latest`, `rust:web`
- `flutter:latest`

All images run as the fixed `vscode` user and include a VS Code-compatible FHS runtime.
They also default to `en_US.UTF-8` with `glibcLocales`, system bash initialization,
bash completion, safe command-not-found suggestions from the local nix-index database,
and a small alias set. Go images add `gobuild-small` for stripped, trimpath builds.

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

Go images also enable the `cgo` library preset by default, so dynamic build libraries feed `CGO_CFLAGS` and `CGO_LDFLAGS`. Rust images enable the `rust-bindgen` preset by default, so build library include paths feed `BINDGEN_EXTRA_CLANG_ARGS`; projects that need bindgen still need to provide `clang`/`libclang` as normal.

Images do not export `LD_LIBRARY_PATH` by default. Set `devcontainer.libraries.exportLdLibraryPath = true` in an image module, or add an explicit `remoteEnv.LD_LIBRARY_PATH` in a project `.devcontainer/devcontainer.json` when a non-Nix toolchain or FFI loader requires it.

Images set `LANG=en_US.UTF-8`, `LANGUAGE=en_US:en`, `LOCALE_ARCHIVE` from
`pkgs.glibcLocales`, `XDG_CONFIG_DIRS=/etc/xdg`, and
`XDG_DATA_DIRS=/usr/local/share:/usr/share:/share`. They intentionally do not set
`LC_ALL`; image modules can set specific `LC_*` variables through `devcontainer.locale.lc`
when a workflow needs a category override.

Shell aliases are image shell behavior, not devcontainer metadata. Modules can extend
`devcontainer.shell.aliases`, and alias names are restricted to a conservative shell-safe
character set.

Do not set `remoteUser`, `containerUser`, or `updateRemoteUserUID` in project `.devcontainer/devcontainer.json`; these images are built for the single `vscode` user. `devcontainer-image check` rejects those overrides, and the image entrypoint refuses to start as another user.

More detail:

- [Architecture](docs/architecture.md)
- [Images](docs/images.md)
- [Remote Docker](docs/docker-remote.md)
- [Development](docs/development.md)
