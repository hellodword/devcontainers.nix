# Architecture

This project is a Nix compiler for VS Code Dev Container images. It is not a collection of Dockerfiles. Image authors describe an image through Nix modules, and the compiler turns those modules into OCI layers, VS Code Dev Containers metadata, runtime helper files, and reports.

The main target platform is `x86_64-linux`.

## Mental Model

There are four concepts to understand first:

1. An image target is a named build such as `go-latest`, `python-web`, or `flutter-latest`.
2. A module writes typed settings. Project-specific image contract remains under `devcontainer.*`, while maintainer-facing NixOS-like subsets such as `environment.*`, `i18n.*`, `time.*`, `security.pki.*`, `programs.*`, and `nix.*` describe static image content.
3. A graph node groups related package paths or generated files into a semantic unit such as `language/go`, `toolset/docker-client`, or `runtime/fonts`.
4. The compiler reads the final module configuration and produces an OCI image plus reports that explain what was built.

The high-level flow is:

```text
flake/targets.nix image target
  -> Nix module evaluation
  -> graph, environment, library, metadata, shell, font, filesystem compilers
  -> layer plan
  -> nix2container OCI image
  -> reports and CI checks
```

The important design choice is that image structure stays declarative. Language modules and toolset modules do not directly create tar files or Docker instructions. They add typed configuration, graph nodes, and tests. The compiler decides how those pieces become image layers and runtime files.

## Inputs And Package Set

The flake pins the dependency set:

- `nixpkgs`
- `rust-overlay`
- `nix-vscode-extensions`
- `nix-index-database`
- `llm-agents`
- `nix2container`

The top-level package set is imported once for `x86_64-linux` with shared nixpkgs policy:

- `allowUnfree = true`
- `android_sdk.accept_license = true`
- `oraclejdk.accept_license = true`
- `allowUnsupportedSystem = true`

Inputs that provide packages are consumed through overlays. That means modules normally use `pkgs.*`, not `inputs.foo.packages.*`. Local package overrides should be added to the flake's `projectOverlays` list so image builds, checks, reports, and runtime helper packages all see the same package set.

## Flake Output Structure

`flake.nix` keeps the top-level assembly small: it pins inputs, imports the package set, creates the compiler, wires image outputs, and exposes packages, apps, checks, and library metadata.

The larger flake internals live under `flake/`:

- `flake/targets.nix` discovers language package versions and defines the image target list.
- `flake/checks.nix` defines report checks, report CLI checks, selected image artifact checks, runtime helper checks, image tar fixtures, composition fixtures, and pure API evaluation checks.
- `flake/workflows.nix` renders per-image GitHub Actions workflows, exposes `generate-workflows`, and checks that generated workflow files are synchronized with the template and target list.

## Image Targets

`flake/targets.nix` defines image targets with:

- a target name, used by local build outputs such as `images.go-latest`
- a family name, used in the registry image name such as `devcontainers-go`
- tags, used in published image references
- one image module under `images/`
- optional override modules for selected language versions

Examples:

| Target | Registry family | Tags | Base module |
| --- | --- | --- | --- |
| `nix-latest` | `devcontainers-nix` | `latest` | `images/nix.nix` |
| `go-latest` | `devcontainers-go` | `latest`, current Go major/minor | `images/go.nix` |
| `go-1-25` | `devcontainers-go` | `1.25` | `images/go.nix` |
| `go-web` | `devcontainers-go` | `web` | `images/go-web.nix` |
| `nodejs-latest` | `devcontainers-nodejs` | `latest`, current Node.js major | `images/nodejs.nix` |
| `nodejs-24` | `devcontainers-nodejs` | `24` | `images/nodejs.nix` |
| `python3` | `devcontainers-python` | `latest`, current Python major/minor | `images/python.nix` |
| `python-web` | `devcontainers-python` | `web` | `images/python-web.nix` |
| `rust-latest` | `devcontainers-rust` | `latest` | `images/rust.nix` |
| `rust-web` | `devcontainers-rust` | `web` | `images/rust-web.nix` |
| `flutter-latest` | `devcontainers-flutter` | `latest` | `images/flutter.nix` |

The published reference for a family is:

```text
ghcr.io/hellodword/devcontainers-<family>:<tag>
```

## Module Layers

Module evaluation starts in `lib/compiler/eval.nix`. It loads these module groups before adding the image-specific modules:

- core modules in `lib/modules/core/`
- static program modules in `lib/modules/programs/`
- toolsets in `lib/modules/toolsets/`
- language runtimes in `lib/modules/runtimes/`
- language stacks in `lib/modules/languages/`

Core modules define the shared image contract: user, filesystem, environment, shell, fonts, native libraries, FHS compatibility, metadata, lifecycle tasks, VS Code extensions, and options.

Toolset modules add common command groups. For example source control tools, fetch/archive tools, search/navigation tools, inspect/debug tools, workflow/format tools, Docker client tools, agent tools, data/network tools, and nix-index tools.

Language modules add language-specific tools, environment variables, VS Code extensions, shell aliases, graph nodes, and smoke tests. For example the Go language module adds Go, `gopls`, Delve, `golangci-lint`, `govulncheck`, the Go VS Code extension, Go cache variables, and the `gobuild-small` alias.

## NixOS-like API Subset

Some maintainer-facing options intentionally reuse familiar NixOS names:

- `environment.systemPackages`, `environment.pathsToLink`, `environment.extraOutputsToInstall`, `environment.etc`, `environment.variables`, `environment.shellAliases`, `environment.shellInit`, and `environment.interactiveShellInit`
- `i18n.defaultLocale`, `i18n.extraLocaleSettings`, and `i18n.glibcLocales`
- `time.timeZone`
- `security.pki.*` for CA certificates only
- `programs.bash`, `programs.git`, `programs.ssh`, `programs.direnv`, `programs.nix-index`, and `programs.nix-ld`
- `nix.settings`

This reuse is scoped to static OCI image generation. The project does not import NixOS modules or imply NixOS runtime semantics. Do not add APIs that require a service manager, daemon lifecycle, PAM, polkit, setuid wrappers, sudo, multi-user account management, or a Docker daemon inside the devcontainer.

Image modules combine these building blocks. For example `images/go.nix` imports the Nix image, enables C, Python, and Node.js runtimes, then enables the Go language module. `images/go-web.nix` imports the Go image and adds data/network tools.

## Graph Nodes

Every substantial package group should have a graph node under `devcontainer.graph.nodes`.

A graph node records:

- `kind`, such as `runtime`, `language`, or `toolset`
- `group`, the layer bucket name
- `paths`, the package paths that belong to the node
- `stability`, used to describe churn
- `sharing`, used to describe reuse across image families
- `priority`, used by reports and planning
- `securityClass`, such as `trusted` or `networked`

The graph gives maintainers a reviewable model of the image. Instead of seeing only a large closure, maintainers can inspect which semantic units were included and where they landed.

## Layer Strategy

OCI runtimes have practical layer-count limits, and GitHub Container Registry rejects oversized layer blobs. These images accumulate language runtimes, tools, extensions, generated files, and Nix store paths, so layer construction must be deterministic and bounded.

The project uses semantic buckets:

- base and FHS runtime
- fonts
- common toolsets
- Nix runtime and Nix language tools
- language runtimes such as Python and Node.js
- language tooling such as Go, Rust, and Flutter
- dynamic runtime and build libraries
- VS Code extensions and generated metadata

`lib/compiler/layers.nix` groups graph nodes by bucket and emits a layer plan. The default budget is 100 semantic buckets with 20 reserved slots. The default maximum layer size is `8GiB`, below the registry's documented 10 GB per-layer limit.

`lib/compiler/image.nix` builds each semantic bucket as an explicit nix2container layer with `maxLayers = 1`. The final customization layer uses a small bounded number of layers for runtime helpers, metadata, generated filesystem files, and the Nix database.

Reports and CI checks enforce this design:

- `layer-plan.json` explains the planned buckets
- image tar checks inspect the final nix2container image JSON
- report checks reject missing buckets, over-budget plans, and invalid image metadata

## Compiler Pipeline

`lib/default.nix` is the compiler orchestrator. `mkImage` evaluates modules once and then runs focused compilers:

- `compileGraph` normalizes graph nodes
- `compileEnvironment` normalizes maintainer-facing packages, variables, shell fragments, `/etc` entries, and buildEnv link settings
- `compileLibraries` builds dynamic runtime and build library profiles
- `compileFhsRuntime` creates compatibility paths and dynamic loader settings
- `compileEnv` merges container, remote, and shell environments
- `compileMetadata` renders Dev Containers metadata
- `compileLifecycle` converts lifecycle tasks into runnable metadata commands
- `compileShell` renders shell startup files
- `compileFonts` renders fontconfig files and reports
- `compileVscodeExtensions` prepares preinstalled VS Code extension payloads
- `compileFilesystem` creates generated root filesystem files
- `compileLayers` creates the semantic layer plan
- `compileImage` creates the nix2container image
- `compileReports` writes machine-readable build reports

Each compiler returns both build artifacts and structured data. Later compilers receive the outputs they need rather than recomputing state. This keeps the flow inspectable and makes reports match the actual image.

## Runtime Filesystem Contract

All images share a single-user runtime contract:

- `User = "vscode"`
- uid/gid `1000`
- `HOME=/home/vscode`
- working directory `/workspaces`
- default command `sleep infinity`
- entrypoint `/usr/local/bin/devcontainer-entrypoint`

Generated filesystem content includes `/etc/passwd`, `/etc/group`, `/etc/os-release`, `/home/vscode`, `/tmp`, `/var/tmp`, `/run/user/1000`, and `/workspaces`.

Project `devcontainer.json` files should not set `remoteUser`, `containerUser`, or `updateRemoteUserUID`. The image metadata already sets the supported values. The image entrypoint refuses to start as another user, and `devcontainer-image check` reports those overrides as errors.

This fixed-user design reduces the number of supported runtime states. It also keeps generated files, Nix profiles, VS Code extension projection, and helper scripts aligned on one home directory and one uid/gid pair.

## Environment Model

The project tracks two configured environment scopes plus generated compiler values:

- `environment.variables` becomes the container environment for the OCI image config and is also exported from generated shell startup files
- `devcontainer.remoteEnv` becomes VS Code Dev Containers metadata only
- FHS runtime and native-library compilers add generated container environment values

`lib/compiler/env.nix` merges configured values with generated values from the FHS runtime and native-library compiler. It also builds `PATH` from ordered path segments, records the origin of each value, expands simple `$VAR` references, and reports conflicts.

The distinction matters because Docker image environment variables, VS Code remote environment variables, and interactive shell variables are applied at different times by different tools.

## FHS Runtime

VS Code server components and many extension helpers expect conventional Linux paths that a pure Nix image does not naturally provide. The FHS runtime adds only the compatibility surface needed for those tools:

- `/bin/bash`
- `/bin/sh`
- `/usr/bin/env`
- common archive and network tools through conventional paths
- architecture dynamic loader path such as `/lib64/ld-linux-x86-64.so.2`
- `NIX_LD` and `NIX_LD_LIBRARY_PATH` from `programs.nix-ld`
- `/usr/lib/libc.so.6`
- `/usr/lib/libstdc++.so.6`
- CA certificate files and environment variables from `security.pki`

The FHS runtime is compatibility glue. It does not turn the image into a general FHS distribution, and modules should not treat it as a reason to bypass Nix store paths when a Nix-native path is available.

## Native Libraries

Command packages and native libraries are separate.

`environment.systemPackages` adds command-line tools and ordinary software to the image and `PATH`.

`devcontainer.libraries.runtime` adds runtime shared-library outputs. These feed `NIX_LD_LIBRARY_PATH` and the dynamic runtime-library profile used by `devpkg add-lib`.

`devcontainer.libraries.build` adds compile/link dependencies. These feed runtime outputs for test execution and expose headers, `pkg-config`, CMake prefixes, `CPATH`, `LIBRARY_PATH`, `NIX_CFLAGS_COMPILE`, and `NIX_LDFLAGS`.

Language modules can add presets:

- Go enables `cgo`
- Rust enables `rust-bindgen`
- Flutter inherits the Rust bindgen preset through its Rust base

`LD_LIBRARY_PATH` is intentionally not exported by default because it changes dynamic loader search order for every process. Projects that need it opt in explicitly through `remoteEnv`, or image modules can opt in with `devcontainer.libraries.exportLdLibraryPath = true`.

## Nix Database And `devpkg`

Images use nix2container's `initializeNixDatabase` support. The generated Nix database registers store paths that already exist in the image, makes `/nix`, `/nix/store`, and `/nix/var/nix` writable by the container user, and avoids startup registration workarounds.

This is required for `devpkg`, which installs ad-hoc packages with `nix profile add`. Without the database, Nix could see store paths on disk that are not registered in `/nix/var/nix/db`, causing profile installs to fail or reference missing paths.

The generated filesystem includes `/etc/nix/nix.conf` from `nix.settings` and `/etc/nixpkgs/config.nix` with the same nixpkgs policy used by the image build. Container environment variables also set nixpkgs policy defaults and `DEVPKG_NIXPKGS_REF=path:<locked-nixpkgs-source>`, so runtime package installs follow the flake-locked nixpkgs input without fetching nixpkgs on first use. The image keeps that source reachable through `/usr/share/devcontainer/nixpkgs` and its `/nix/store/...-source` target. `devpkg` runs flake evaluation and installation commands with `--impure` so packages such as Google Chrome and Microsoft Edge can read those defaults.

The `devpkg` runtime package also ships Bash completion under `/share/bash-completion/completions/devpkg`. It completes subcommands, common options, installed profile entries, and nixpkgs package attributes from the same locked nixpkgs source.

## Locale, Shell, And Fonts

The default locale contract is:

- `LANG=en_US.UTF-8`
- `LANGUAGE=en_US:en`
- `LOCALE_ARCHIVE` from `pkgs.glibcLocales`
- no default `LC_ALL`

`LC_ALL` is intentionally unset because it overrides every locale category. Image modules can set specific `LC_*` variables through `i18n.extraLocaleSettings`.

Generated shell files are `/etc/profile`, `/etc/bashrc`, and `/etc/bash.bashrc`. Interactive Bash gets aliases, a lightweight prompt, history settings, bash completion, and a command-not-found handler. The handler only queries the local nix-index database and returns 127. It does not install software, call the network, or execute project commands.

All images include fontconfig and Noto Latin, CJK, symbol, and emoji coverage. Fontconfig defaults prefer Simplified Chinese CJK families for generic sans, serif, and monospace aliases. See [Fonts And Fontconfig](fonts-fontconfig.md) for the detailed font design.

## VS Code Metadata And Extensions

The OCI image label `devcontainer.metadata` is a JSON array. It contains the computed Dev Containers metadata for users, environment, lifecycle commands, and VS Code customizations.

VS Code extension support has two parts:

- modules declare extension identifiers and settings
- the extension compiler prepares extension payloads and metadata for projection into VS Code server extension directories

Lifecycle tasks are declared as structured Nix module values. The lifecycle compiler turns them into metadata commands that call `devcontainer-task-runner`, which gives the project one consistent place for task ordering, once-only behavior, timeouts, and user validation.

## Reports And Checks

Reports are part of the architecture, not just debug output. They make image composition visible without unpacking an OCI artifact.

Important reports include:

- graph reports
- package reports
- environment reports
- metadata label reports
- lifecycle reports
- shell reports
- fontconfig reports
- VS Code extension reports
- FHS runtime reports
- layer plans
- smoke test plans
- CI plans

Checks use those reports to reject regressions before an image is published. Smoke tests then validate runtime behavior after an image is loaded into Docker.

`flake/checks.nix` owns the Nix check set. `flake/workflows.nix` adds a generated workflow sync check so target changes and template changes are reflected in checked-in `build-image-*.yml` files.

## Security Boundaries

The images avoid expanding privileges by default:

- they run as the fixed `vscode` user
- they include Docker client tools but do not run a Docker daemon
- they do not mount a host Docker socket
- they do not expose `services.*`, sudo, PAM, polkit, setuid wrapper, or multi-user APIs
- command-not-found suggestions are local database lookups only
- Chromium sandbox workarounds are not forced globally
- native library search paths are explicit and do not export `LD_LIBRARY_PATH` by default

When a feature needs broader runtime access, the project should document the security model and make the user opt in through project configuration.

## How To Extend The Design

When adding a feature, decide which layer of the design owns it:

- user-facing image behavior usually belongs in a module
- shared generated files usually belong in a focused compiler
- runtime commands belong under `runtime/`
- repeated package groups should become graph nodes
- user-visible behavior should have smoke tests
- compiler behavior should have report checks
- browser, font, or Docker daemon behavior should be documented because those areas have important runtime constraints

The goal is for every new behavior to appear in the module config, the graph, the image, and the reports in a way a maintainer can inspect.
