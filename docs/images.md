# Images

All images include the base Nix/FHS runtime, source control tools, archive/fetch tools, navigation tools, debug tools, and format/workflow tools.

## `nix`

Includes Nix, `nixd`, `nil`, `nixfmt`, `alejandra`, `statix`, `deadnix`, and `treefmt`.

## `python`

Adds Python runtime and Python tooling: `uv`, `uvx`, `pipx`, `ruff`, `mypy`, `pytest`, `ipython`, `black`, `pylint`, and `bandit`. Node.js runtime is included for common Python tooling integrations.

## `nodejs`

Adds Node.js runtime and tooling: `pnpm`, `yarn`, TypeScript, ESLint, Prettier, and `node-gyp`. Python and C build runtimes are included for native package builds.

## `go`

Adds Go, `gopls`, Delve, `golangci-lint`, `gotools`, and `govulncheck`. Python, Node.js, and C build runtimes are included. Go images also define `gobuild-small` as an alias for `go build -trimpath -ldflags "-s -w -buildid="`.

## `rust`

Adds the latest nightly Rust binary toolchain from `rust-overlay`, including `rustc`, `cargo`, `rustfmt`, `clippy`, `rust-analyzer`, and `rust-src`, plus `cargo-nextest`, `cargo-edit`, and `cargo-audit`.

## Web Variants

`python-web`, `go-web`, and `rust-web` add data/network tools such as SQLite, PostgreSQL, Redis, and HTTPie. They also include Node.js language tooling for web workflows.

## `flutter`

Adds Flutter, Dart, JDK, Gradle, Android tools, Chromium, and GUI/GPU diagnostics. It imports the Rust image and includes Node.js language tooling.

## Common Toolsets

Every image includes:

- source control, fetch/archive, search/navigation, inspect/debug, and workflow-format tools
- a VS Code-compatible glibc runtime exposed through conventional FHS paths
- a fixed `vscode` user; project devcontainer JSON must not override `remoteUser`, `containerUser`, or `updateRemoteUserUID`
- `devpkg` for ad-hoc user installs from `nixpkgs`, for example `devpkg add cowsay`
- separate dynamic native-library profiles, for example `devpkg add-lib zlib` for runtime-only libraries and `devpkg add-dev-lib openssl zlib` for headers plus link/runtime outputs
- `en_US.UTF-8` locale defaults backed by `pkgs.glibcLocales`
- system `/etc/profile`, `/etc/bashrc`, `/etc/bash.bashrc`, default aliases, bash completion, and local nix-index based `command_not_found_handle`

Dynamic build libraries are discoverable through `PKG_CONFIG_PATH`, `CMAKE_PREFIX_PATH`, `NIXPKGS_CMAKE_PREFIX_PATH`, `CPATH`, `LIBRARY_PATH`, `NIX_CFLAGS_COMPILE`, and `NIX_LDFLAGS`. `LD_LIBRARY_PATH` is intentionally absent unless an image or project opts in.

Go images enable the `cgo` preset, adding `CGO_CFLAGS` and `CGO_LDFLAGS` for dynamically installed build libraries. Rust images, including Flutter through its Rust base, enable the `rust-bindgen` preset, adding `BINDGEN_EXTRA_CLANG_ARGS` for bindgen include discovery. The bindgen preset does not install `clang` or `libclang`; add those explicitly if a project needs them.

Example `.devcontainer/devcontainer.json` for dynamic build libraries:

```json
{
  "name": "go",
  "image": "ghcr.io/hellodword/devcontainers-go:latest",
  "postCreateCommand": "devpkg add-dev-lib openssl zlib"
}
```

Runtime-only FFI library:

```json
{
  "name": "ffi-runtime",
  "image": "ghcr.io/hellodword/devcontainers-go:latest",
  "postCreateCommand": "devpkg add-lib libGL"
}
```

Explicit outputs:

```json
{
  "name": "static-zlib",
  "image": "ghcr.io/hellodword/devcontainers-go:latest",
  "postCreateCommand": "devpkg add-dev-lib --outputs out,dev,static zlib"
}
```

Project-level `LD_LIBRARY_PATH` opt-in:

```json
{
  "name": "ffi",
  "image": "ghcr.io/hellodword/devcontainers-go:latest",
  "postCreateCommand": "devpkg add-dev-lib openssl zlib",
  "remoteEnv": {
    "LD_LIBRARY_PATH": "/home/vscode/.local/share/devpkg/runtime-libraries/profile/lib:/home/vscode/.local/share/devpkg/build-libraries/profile/lib:${containerEnv:LD_LIBRARY_PATH}"
  }
}
```

Images do not set `DOCKER_HOST` by default and do not run a Docker daemon.

The full glibc locale archive is included for predictable UTF-8 behavior in non-NixOS containers. This costs more image space than a custom trimmed archive, but avoids locale failures in common CLI and language tooling. Images set `LANG` and `LANGUAGE`; they do not set `LC_ALL` by default so projects can override specific locale categories with `LC_CTYPE`, `LC_TIME`, or other `LC_*` variables.
