# Built-in Toolchains, `devpkg`, and Offline `devShell` Reuse

## Built-in Language and Format Toolchains

All language toolchains reside in `/nix/store` (`Layer 2`), linked into `/usr/bin`, anchored by `/nix/var/nix/gcroots/docker/` GC roots, and paired with 26 offline VS Code extensions plus declarative cache environment variables from [`data/cache-layout.json`](../data/cache-layout.json).

### Included Toolchain Matrix

- **C / C++ & Build Systems**: `gcc`, `binutils`, `ccache` (`CCACHE_MAXSIZE=20G`), `pkg-config`, `cmake`, `ninja`, `meson`, `muon`, `gnumake`, `autoconf`, `automake`, `libtool`, plus `glibc.dev`, `patchelf`, `stdenv`, and `zlib` headers/libraries in `/nix/store`.
- **Rust**: Nightly `rustc`, `cargo`, `rust-src`, `rustfmt`, `clippy`, `rust-analyzer`, `cargo-nextest`, `cargo-edit`, `cargo-audit`, and `rustup`.
- **Go**: `go`, `gopls`, `dlv` (`delve`), `golangci-lint`, `gotools`, `govulncheck`, `gotests`, `gomodifytags`, `impl`, and `protoc-gen-go`.
- **Python**: `python3`, `pip`, `uv`, `pipx`, `ruff`, `mypy`, `pytest`, `ipython`, `black`, `pylint`, and `bandit`.
- **Node.js, TypeScript & Web**: `node`, `npm`, `corepack`, `pnpm`, `yarn`, `tsc` (`typescript`), `typescript-language-server`, `eslint`, `node-gyp`, `vue-language-server`, `tailwindcss-language-server`, and `stylelint`.
- **Nix**: `nixd`, `nil`, `nixfmt`, `alejandra`, `statix`, `deadnix`, `treefmt`, `nix-index` (`nix-locate`), `comma` (`,`), and `man`.
- **Formats, Linting & Protobuf**: `just`, `just-lsp`, `prettier`, `shellcheck`, `shfmt`, `editorconfig`, `taplo`, `yaml-language-server`, `lemminx`, `minijinja-cli`, `protoc`, `protols`, `buf`, `protolint`, `grpcurl`, `api-linter`, and `wayland-info`.

## Rust Nightly Default and Pinning Project Versions

The image ships the **Rust Nightly** toolchain by default (including `rust-src`, `rustfmt`, `clippy`, and `rust-analyzer`) rather than Rust Stable. `/usr/bin/rustc` and `/usr/bin/cargo` invoke this pre-installed Nightly toolchain directly offline, while `/usr/bin/rustup` is available on `PATH` for project-level toolchain management.

Projects that require **Rust Stable** or a **specific compiler version** use one of two standard approaches:

1. **Declarative `flake.nix` `devShell` (recommended for Nix projects and offline reproducibility)**:
   Pin the desired channel or version with `oxalica/rust-overlay` in the project's `flake.nix`:

   ```nix
   devShells.x86_64-linux.default = pkgs.mkShell {
     packages = [
       pkgs.rust-bin.stable."1.85.0".default
     ];
   };
   ```

   Enter the shell with `nix develop`.

2. **`rust-toolchain.toml` with `rustup` (for standard Cargo repositories)**:
   Commit a `rust-toolchain.toml` at the repository root:
   ```toml
   [toolchain]
   channel = "stable"
   components = ["rustfmt", "clippy", "rust-analyzer"]
   ```
   Install and activate the pinned toolchain inside user-owned `RUSTUP_HOME` (`/home/vscode/.local/share/rustup`) via `rustup toolchain install`, or prepend `/home/vscode/.local/share/cargo/bin` after running `rustup default stable`.

## Ad-Hoc Packages and Libraries with `devpkg`

The image bundles the locked `nixpkgs` source tree at `/usr/share/devcontainer/nixpkgs`. Use `devpkg` to manage user-scoped CLI packages, runtime shared libraries (`NIX_LD_LIBRARY_PATH`), and C/C++ build headers (`CPATH`, `LIBRARY_PATH`, `PKG_CONFIG_PATH`, `CMAKE_PREFIX_PATH`) without root privileges:

```bash
# Install, list, and remove CLI tools in the user Nix profile
devpkg add patchelf
devpkg list --json
devpkg remove patchelf

# Expose shared libraries to dynamically linked binaries via nix-ld
devpkg add-lib zlib
devpkg list-lib

# Expose headers, static/shared libraries, and pkg-config files to compilers
devpkg add-dev-lib zlib openssl
devpkg list-dev-lib
devpkg remove-dev-lib openssl
```

Packages whose store closures already exist in the image install instantaneously even with `--network none`.

## Offline `devShell` Store Reuse

Running `nix-store --gc` inside a container collects unreferenced temporary builds while preserving every pre-baked toolchain path, `stdenv`, `/usr/share/devcontainer/nixpkgs`, and `/usr/share/devcontainer/rust-overlay` via `/nix/var/nix/gcroots/docker/`.

When a project locks the matching `nixpkgs` tree (or references `path:/usr/share/devcontainer/nixpkgs`), `nix develop --offline` evaluates and enters the shell with zero network downloads:

```bash
nix develop --offline --command cargo build --offline
```
