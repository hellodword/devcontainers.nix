# Images

All images include the base Nix/FHS runtime, Docker CLI tools, Codex CLI, nix-index database tools, source control tools, archive/fetch tools, navigation tools, debug tools, and format/workflow tools.

## `nix`

Includes Nix, `nixd`, `nil`, `nixfmt-rfc-style`, `alejandra`, `statix`, `deadnix`, and `treefmt`.

## `python`

Adds Python runtime and Python tooling: `uv`, `uvx`, `pipx`, `ruff`, `mypy`, `pytest`, `ipython`, `black`, `pylint`, and `bandit`. Node.js runtime is included for common Python tooling integrations.

## `nodejs`

Adds Node.js runtime and tooling: `pnpm`, `yarn`, TypeScript, ESLint, Prettier, and `node-gyp`. Python and C build runtimes are included for native package builds.

## `go`

Adds Go, `gopls`, Delve, `golangci-lint`, `gotools`, and `govulncheck`. Python, Node.js, and C build runtimes are included.

## `rust`

Adds the stable Rust binary toolchain from `rust-overlay`, including `rustc`, `cargo`, `rustfmt`, `clippy`, `rust-analyzer`, and `rust-src`, plus `cargo-nextest`, `cargo-edit`, and `cargo-audit`.

## Web Variants

`python-web`, `go-web`, and `rust-web` add data/network tools such as SQLite, PostgreSQL, Redis, and HTTPie. They also include Node.js language tooling for web workflows.

## `flutter`

Adds Flutter, Dart, JDK, Gradle, Android tools, Chromium, and GUI/GPU diagnostics. It imports the Rust image and includes Node.js language tooling.

## Common Toolsets

Every image includes:

- Docker client: `docker`, `docker buildx`, `docker compose`, credential helpers
- Codex CLI from `llm-agents.nix`
- nix-index database tools: `nix-index`, `nix-locate`, and `comma` when available

Images do not set `DOCKER_HOST` by default and do not run a Docker daemon.
