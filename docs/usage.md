# Usage

This guide covers the published images in VS Code Dev Containers and plain Docker.

For the full image list, see [README: Quick Start](../README.md#quick-start).
For intent-based navigation, see [Documentation Index](index.md).

## Basic Devcontainer

Create `.devcontainer/devcontainer.json` with one published image reference:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest"
}
```

Use the Flutter image from the README only when the project also needs Flutter,
Dart, Android, or the bundled browser workflow.

When migrating from an older release, replace every `devcontainers-nix`,
`devcontainers-go`, `devcontainers-nodejs`, `devcontainers-python3`, or
`devcontainers-rust` reference—including versioned and `web` tags—with
`ghcr.io/hellodword/devcontainers-dev:latest`. The Flutter reference remains
`ghcr.io/hellodword/devcontainers-flutter:latest` and now includes the complete
dev tool stack.

## Runtime Defaults

Published images run as the fixed `vscode` user with uid/gid `1000:1000`.

Do not set these fields in project `devcontainer.json`:

```json
{
  "remoteUser": "root",
  "containerUser": "root",
  "updateRemoteUserUID": true,
  "runArgs": ["--user", "1000:100"]
}
```

The image metadata sets the supported users, `updateRemoteUserUID=false`,
`init=true`, and `overrideCommand=false`. This keeps the image entrypoint active
even with the one-field configuration above. `devcontainer-image check` reports
project user-name and Docker user overrides as invalid.

When a project needs the container UID/GID to match the host user, derive a
small project-local image at build time. Keep the account names fixed and only
change the numeric ids.

Example `.devcontainer/devcontainer.json`:

```json
{
  "build": {
    "dockerfile": "Dockerfile",
    "args": {
      "DEV_UID": "1000",
      "DEV_GID": "100"
    }
  }
}
```

Example `.devcontainer/Dockerfile`:

```dockerfile
FROM ghcr.io/hellodword/devcontainers-dev:latest

USER root
ARG DEV_UID=1000
ARG DEV_GID=1000
RUN /usr/bin/devcontainer-set-user-id --uid "$DEV_UID" --gid "$DEV_GID"
ENV XDG_RUNTIME_DIR=/run/user/${DEV_UID}
USER vscode
```

Set the build arguments to the host values from `id -u` and `id -g`, then rebuild.
The account names and home stay `vscode:vscode` and `/home/vscode`. Dev Containers
must finish this change during the build, before its startup probes inspect the
account. The plain-Docker runtime mode below is not a Dev Containers configuration.

The image metadata also mounts the project `.devcontainer` directory back onto
`/workspaces/${localWorkspaceFolderBasename}/.devcontainer` as a read-only bind
mount. This prevents processes running as `vscode` inside the container from
editing `devcontainer.json` and planting a later `initializeCommand` that would
run on the host during rebuild. This protects containers created after the
metadata is trusted; it does not validate a `.devcontainer` that was already
malicious before the first open. If you use a custom `workspaceMount`,
`workspaceFolder`, or Docker Compose layout, add an equivalent read-only mount
for the workspace root's `.devcontainer` directory.

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

## Plain Docker

The default invocation needs no setup commands:

```sh
docker run --rm -it \
  -v "$PWD:/workspaces/project" -w /workspaces/project \
  -p 8080:8080 \
  ghcr.io/hellodword/devcontainers-dev:latest bash
```

The entrypoint prepares user directories and machine-id, then runs the command
as `vscode`. It starts Tini when it is PID 1. With `docker run --init`, Docker's
init handles that job. Bash keeps interactive Ctrl-C and job control. Omitting
the command runs `sleep infinity`.

To select numeric IDs at container startup:

```sh
docker run --rm -it --user 0 \
  -e DEVCONTAINER_UID="$(id -u)" -e DEVCONTAINER_GID="$(id -g)" \
  -e XDG_RUNTIME_DIR="/run/user/$(id -u)" \
  -v "$PWD:/workspaces/project" -w /workspaces/project \
  ghcr.io/hellodword/devcontainers-dev:latest bash
```

Startup validates the IDs, updates the fixed account and container-owned state,
then drops privileges before running user code. IDs must be decimal integers in
`1..2147483647`; an omitted ID keeps the account's existing value. A conflicting
account or a non-root attempt to change IDs fails. Starting as root without an
ID request also fails.

Docker still records the container's configured user as root in this mode.
Use `docker exec --user vscode <container> <command>` for later commands. Setting
`XDG_RUNTIME_DIR` in the invocation also gives those exec commands the correct
environment; environment changes inside an entrypoint do not update Docker's
stored configuration.

Project/data bind mounts and nested cache mounts are left untouched. The helper
skips mounted contents and preserves root-owned image files. It does not repair
host permissions. Replacing the entire home or sharing `/nix` across containers
is outside this mode. Nix remains a per-container, single-user installation;
profiles, builds, optimisation and garbage collection continue to use its local
store and image GC roots.

## Machine Identity And Linux Basics

The image contains an empty machine-id placeholder. First startup generates a
random ID; restarting the same container retains it. Creating or rebuilding a
container generates a new ID. `/etc/machine-id` and `/var/lib/dbus/machine-id`
resolve to the same container-owned state file.

For an explicitly fixed identity, pass
`-e DEVCONTAINER_MACHINE_ID=1234567890abcdef1234567890abcdef`, or mount a file:

```sh
docker run --rm \
  --mount "type=bind,src=$PWD/container-machine-id,dst=/etc/machine-id,readonly" \
  ghcr.io/hellodword/devcontainers-dev:latest cat /etc/machine-id
```

The file must contain 32 lowercase hexadecimal characters, nonzero, optionally
followed by one newline. Empty or malformed mounted files fail startup. If both
an existing ID and the environment variable are present, they must match.
Startup never overwrites a valid existing identity or logs its value.

The baseline includes libc user/host/service/protocol lookup configuration,
`getent`, `/etc/shells`, ncurses tools and terminfo, MIME data and `gio`, standard
zoneinfo paths, UTF-8 locales, and CA certificates. `/tmp` and `/var/tmp` have mode
1777; the user's runtime directory has mode 0700. Docker supplies hostnames,
resolver files, `/proc`, and `/dev`.

Applications that need a session bus can run:

```sh
dbus-run-session -- your-application
```

The bus ends with the application. No persistent D-Bus service, systemd, SSH
server, cron, or full desktop session starts automatically.

Explicit environment values survive login and interactive shell startup. PATH
still merges image tools with caller paths, and workspace variables still bind
when `WORKSPACE` is available. Changing one XDG variable does not recalculate
other variables. The default `XDG_RUNTIME_DIR` follows the actual UID; a custom
absolute runtime path is preserved and must belong to the user with mode 0700.

## Lifecycle Tasks

Images run structured lifecycle tasks through `devcontainer-task-runner`.
Inspect the configured task graph without executing it:

```sh
devcontainer-task-runner plan postCreate
```

The plan output is JSON and includes the phase roots, dependency tree,
topological order, once-task status, and whether each task would run now.
Task logs and helper diagnostics use best-effort redaction for common token,
password, key, Authorization, GitHub, npm, cloud credential, and SAS signature
formats. This redaction is not a secret scanner; keep secrets out of image
modules and lifecycle commands.

## VS Code Settings

Project-local VS Code settings belong in Dev Containers metadata:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
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
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
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
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
  "postCreateCommand": "devpkg add-lib libGL"
}
```

Build libraries are for compiling and linking. They expose headers,
`pkg-config`, CMake prefixes, compiler wrapper flags, and runtime outputs:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
  "postCreateCommand": "devpkg add-dev-lib openssl zlib"
}
```

Select explicit package outputs when a project needs them:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
  "postCreateCommand": "devpkg add-dev-lib --outputs out,dev,static zlib"
}
```

The dev and Flutter images enable the `cgo` library preset, so dynamically installed build
libraries also feed `CGO_CFLAGS` and `CGO_LDFLAGS`.

The dev and Flutter images enable the `rust-bindgen` preset, so build library
include paths feed `BINDGEN_EXTRA_CLANG_ARGS`. Projects that use bindgen still
need to install `clang` and `libclang` when their build requires those tools:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
  "postCreateCommand": "devpkg add clang && devpkg add-dev-lib llvmPackages.libclang openssl"
}
```

If a non-Nix toolchain or FFI loader needs `LD_LIBRARY_PATH`, opt in explicitly:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
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
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
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
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
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
    image: ghcr.io/hellodword/devcontainers-dev:latest
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
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
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
    image: ghcr.io/hellodword/devcontainers-dev:latest
    runtime: runsc
```
