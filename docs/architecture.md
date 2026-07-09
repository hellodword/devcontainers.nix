# Architecture

This project is a Nix compiler for VS Code Dev Container images. It is not a collection of Dockerfiles. Image authors describe an image through Nix modules, and the compiler turns those modules into OCI layers, VS Code Dev Containers metadata, runtime helper files, and reports.

The main target platform is `x86_64-linux`.

## Mental Model

There are four concepts to understand first:

1. An image target is a named build such as `go`, `python3-web`, or `flutter`.
2. Module evaluation produces typed configuration. Project-specific image contract remains under `devcontainer.*`, while maintainer-facing NixOS-like subsets such as `environment.*`, `i18n.*`, `time.*`, `security.pki.*`, `programs.*`, and `nix.*` describe static image content.
3. `devcontainer.profiles` is the main maintenance surface for reusable image content. Leaf profiles describe packages, environment, VS Code metadata, lifecycle tasks, smoke cases, and library presets. Bundle profiles include other profiles.
4. The compiler expands the enabled profile graph, turns profiles into graph nodes, then produces environment data, layers, an OCI image, smoke plans, and reports that explain what was built.

The high-level flow is:

```text
images/default.nix image target
  -> Nix module evaluation
  -> profile compiler
  -> graph, environment, library, metadata, test-plan, shell, font, filesystem compilers
  -> layer plan
  -> nix2container OCI image
  -> reports and CI checks
```

The important design choice is that image structure stays declarative. Language, runtime, editor, and toolset modules normally define profiles and enable profiles. The profile compiler decides which packages, graph nodes, VS Code extensions, environment fragments, lifecycle tasks, library presets, and smoke cases become effective. Later compilers decide how those pieces become image layers, runtime files, reports, and smoke plans.

## Inputs And Package Set

The flake pins the dependency set:

- `nixpkgs`
- `rust-overlay`
- `nix-vscode-extensions`
- `nix-index-database`
- `agents-misc`
- `nix2container`

The top-level package set is imported once for `x86_64-linux` with shared nixpkgs policy:

- `allowUnfree = true`
- `android_sdk.accept_license = true`
- `oraclejdk.accept_license = true`
- `allowUnsupportedSystem = true`

Inputs that provide packages are consumed through overlays. That means modules normally use `pkgs.*`, not `inputs.foo.packages.*`. Local package overrides should be added to the flake's `projectOverlays` list so image builds, checks, reports, and runtime helper packages all see the same package set.

## Flake Output Structure

`flake.nix` keeps the top-level assembly small: it pins inputs, imports the package set, creates the compiler, wires image outputs, and exposes packages, apps, checks, and library metadata.

The target registry lives in `images/default.nix`; it discovers language package
versions and defines the image target list next to the image modules it owns.
Target records are the owner for image identity, documentation `use when` text,
workflow E2E opt-in sessions, and image-specific check policy.

The larger flake internals live under `flake/`:

- `flake/docs.nix` renders checked-in documentation snippets from target and E2E session metadata and exposes `generate-docs`.
- `flake/checks.nix` aggregates focused check suites under `flake/checks/`: contracts, tooling, artifacts, and report CLI behavior.
- `flake/e2e.nix` exposes heavy VS Code GUI Dev Containers tests under the custom `e2e.${system}` output.

## Image Targets

`images/default.nix` defines image targets with:

- a target name, used by local build outputs such as `images.go`
- a family name, used in the registry image name such as `devcontainers-go`
- tags, used in published image references
- one image module under `images/`
- `docs.useWhen`, the target's user-facing selection hint validated by
  contract checks
- optional `checks`, used by required-target, report CLI, and rootfs checks
- optional override modules for selected language versions

Examples:

<!-- BEGIN GENERATED:image-targets -->

| Target        | Registry family         | Tags             | Base module              |
| ------------- | ----------------------- | ---------------- | ------------------------ |
| `nix`         | `devcontainers-nix`     | `latest`         | `images/nix.nix`         |
| `go`          | `devcontainers-go`      | `latest`, `1.26` | `images/go.nix`          |
| `go-web`      | `devcontainers-go`      | `web`            | `images/go-web.nix`      |
| `nodejs`      | `devcontainers-nodejs`  | `latest`, `26`   | `images/nodejs.nix`      |
| `python3`     | `devcontainers-python3` | `latest`, `3.13` | `images/python.nix`      |
| `python3-web` | `devcontainers-python3` | `web`            | `images/python3-web.nix` |
| `rust`        | `devcontainers-rust`    | `latest`         | `images/rust.nix`        |
| `rust-web`    | `devcontainers-rust`    | `web`            | `images/rust-web.nix`    |
| `flutter`     | `devcontainers-flutter` | `latest`         | `images/flutter.nix`     |

<!-- END GENERATED:image-targets -->

The published reference for a family is:

```text
ghcr.io/hellodword/devcontainers-<family>:<tag>
```

`flake/docs.nix` and focused checks consume this target registry. They should
not keep separate image-name or image-documentation registries.

## Module Layers

Module evaluation starts in `lib/compiler/eval.nix`. It imports the module registry in `lib/modules/default.nix`, which scans ordinary `.nix` files in these module groups before adding the image-specific modules:

- core modules in `lib/modules/core/`
- editor profiles in `lib/modules/editor/`
- static program modules in `lib/modules/programs/`
- toolsets in `lib/modules/toolsets/`
- small tool profiles in `lib/modules/tools/`
- language runtimes in `lib/modules/runtimes/`
- language stacks in `lib/modules/languages/`

Core modules define the shared image contract: user, filesystem, environment, shell, fonts, native libraries, FHS compatibility, PATH, metadata, and lifecycle tasks.

Owner modules declare their typed options, profile definitions, and bucket definitions next to the behavior they implement. Adding a normal module file under one of the groups above does not require changing the compiler loader.

Toolset modules add common command groups by declaring profiles. For example source control tools, fetch/archive tools, search/navigation tools, inspect/debug tools, workflow/format tools, Docker client tools, agent tools, data/network tools, and nix-index tools.

Language modules add language-specific tools, environment variables, VS Code extensions, shell aliases, and smoke cases through profiles. For example the Go language profile adds Go, `gopls`, Delve, `golangci-lint`, `govulncheck`, the Go VS Code extension, Go cache variables, the `gobuild-small` alias, and the `language.go` smoke case.

## NixOS-like API Subset

Some maintainer-facing options intentionally reuse familiar NixOS names:

- `environment.systemPackages`, `environment.pathsToLink`, `environment.extraOutputsToInstall`, `environment.etc`, `environment.variables`, `environment.shellAliases`, `environment.shellInit`, and `environment.interactiveShellInit`
- `i18n.defaultLocale`, `i18n.extraLocaleSettings`, and `i18n.glibcLocales`
- `time.timeZone`
- `security.pki.*` for CA certificates only
- `programs.bash`, `programs.git`, `programs.ssh`, `programs.nix-index`, and `programs.nix-ld`
- `nix.settings`

This reuse is scoped to static OCI image generation. The project does not import NixOS modules or imply NixOS runtime semantics. Do not add APIs that require a service manager, daemon lifecycle, PAM, polkit, setuid wrappers, sudo, multi-user account management, or a Docker daemon inside the devcontainer.

Image modules combine these building blocks. For example `images/go.nix` imports the Nix image, enables C, Python, and Node.js runtimes, then enables the Go language module. `images/go-web.nix` imports the Go image and adds data/network tools.

## Profiles

`devcontainer.profiles` is the profile-first compiler input for reusable image content.

A profile has an `id`, `kind`, semantic layer `group`, priority, stability, sharing, and security class. Enabled leaf profiles can contribute packages, provided command IDs, VS Code extensions and settings, environment variables, PATH segments, shell aliases, lifecycle tasks, library presets, and smoke cases. Enabled bundle profiles contain only `includes`; they are a named way to activate a set of other profiles.

Bundle profiles must stay resource-free. When a bundle needs smoke coverage for the behavior created by its included profiles, it includes a zero-package smoke-only leaf profile that owns the case. Core modules can still declare top-level smoke cases for shared image behavior.

Profile definitions belong in the module that owns the behavior. For example, editor bundles live in editor modules, language bundles live in language modules, toolset bundles live in toolset modules, and image-specific smoke-only profiles live in image modules.

The profile compiler runs before graph, environment, metadata, lifecycle, VS Code extension, and test-plan compilers. It:

- expands root-enabled profiles and includes
- rejects unknown includes and include cycles
- enforces the leaf-vs-bundle split
- validates layer buckets, PATH buckets, extension buckets, extension ownership, lifecycle task names, and VS Code companion tools
- creates graph nodes automatically for effective leaf profiles
- writes `profile-report.json`

Image modules should generally enable existing profiles instead of adding packages or graph nodes directly. New language stacks, reusable toolsets, editor integrations, and small tools should define profiles first. Direct `devcontainer.graph.nodes` writes are reserved for compiler-owned or core generated content such as FHS compatibility roots, fonts, shell files, filesystem roots, and dynamic library profiles.

## Graph Nodes

Every substantial package group should have a graph node. Most package groups get one automatically from their enabled profile. Compiler-owned generated content may still define a node directly under `devcontainer.graph.nodes`.

A graph node records:

- `kind`, such as `runtime`, `language`, or `toolset`
- `group`, the layer bucket name
- `paths`, the package paths that belong to the node
- `stability`, used to describe churn
- `sharing`, used to describe reuse across image families
- `priority`, used by reports and planning
- `securityClass`, such as `trusted` or `networked`

The graph gives maintainers a reviewable model of the image. Instead of seeing only a large closure, maintainers can inspect which semantic units were included, whether they came from profiles or compiler-generated content, and where they landed.

## Layer Strategy

OCI runtimes have practical layer-count limits, and GitHub Container Registry rejects oversized layer blobs. These images accumulate language runtimes, tools, extensions, generated files, and Nix store paths, so layer construction must be deterministic and bounded.

The project uses semantic layer buckets. Bucket names are semantic identifiers
such as `base-runtime`, `python-language`, and `vscode-extensions-python`.
Ordering comes only from each bucket definition's `order` value.

- base and FHS runtime
- fonts
- common toolsets
- Nix runtime and Nix language tools
- language runtimes such as Python and Node.js
- language tooling such as Go, Rust, and Flutter
- dynamic runtime and build libraries
- VS Code extensions and generated metadata

`lib/compiler/layers.nix` groups graph nodes by bucket and emits a layer plan. The default final layer budget is 100 layers with 20 slots reserved for non-semantic image construction, leaving 80 semantic buckets by default. The default maximum layer size is `8GiB`, below the registry's documented 10 GB per-layer limit.

Layer bucket order is derived from owner-local
`devcontainer.layers.bucketDefinitions`. PATH order is derived from
`devcontainer.path.bucketDefinitions`. This keeps the global ordering stable
while letting each owner declare the bucket it needs.

Layer bucket orders use sparse semantic ranges:

| Range         | Purpose                                      |
| ------------- | -------------------------------------------- |
| `00000-09999` | Core and bootstrap runtime buckets           |
| `10000-19999` | Common tools, Nix support, and shell runtime |
| `20000-39999` | Language and runtime stacks                  |
| `50000-59999` | Runtime and build libraries                  |
| `60000-69999` | VS Code extension buckets                    |
| `80000-89999` | Lifecycle and generated runtime buckets      |
| `90000-99999` | Dynamic and fallback buckets                 |

New layer buckets normally use `100`-step spacing inside the relevant semantic
range. Insertions between existing adjacent buckets may use `10`-step spacing.
`contracts-bucket-registry` rejects duplicate order values, negative order
values, and non-`10`-aligned order values.

Layer order and PATH order are both sorted ascending, but they mean different
things. A smaller layer order means an earlier, lower-level, more stable image
construction position. A smaller PATH order means the segment appears earlier in
`PATH` and has higher command lookup precedence.

`lib/compiler/image.nix` builds each semantic bucket as an explicit nix2container layer with `maxLayers = 1`. The final customization layer uses a small bounded number of layers for runtime helpers, metadata, generated filesystem files, and the Nix database. `devcontainer.layers.max` is the final OCI layer budget, `reserve` is held back for non-semantic layers, and `semanticMax` is computed as `max - reserve`.

Reports and CI checks enforce this design:

- `layer-plan.json` explains the planned buckets and semantic layer budget
- `layer-closure-report.json` records real NAR closure sizes for each semantic bucket
- image tar and package checks inspect the final nix2container image JSON and fail when layer count or actual OCI layer size exceeds budget
- report checks reject missing buckets, over-budget plans, and invalid image metadata
- `contracts-module-registry` and `contracts-bucket-registry` reject missing module registration and missing or unstable bucket definitions

## Compiler Pipeline

`lib/default.nix` is the compiler orchestrator. `mkImage` evaluates modules once and then runs focused compilers:

- `compileProfiles` expands root-enabled profiles, validates composition rules, creates profile graph nodes, and prepares `profile-report.json`
- `compileEnvironment` normalizes maintainer-facing packages, variables, shell fragments, `/etc` entries, buildEnv link settings, and package contributions from profiles
- `compileLibraries` builds dynamic runtime and build library profiles, including presets from profiles
- `compileGraph` normalizes explicit graph nodes plus automatic graph nodes from profiles
- `compileFhsRuntime` creates compatibility paths and dynamic loader settings
- `compileEnv` merges container, remote, shell, and profile environment fragments
- `compileLifecycle` converts lifecycle tasks into runnable metadata commands
- `compileShell` renders shell startup files
- `compileFonts` renders fontconfig files and reports
- `compileVscodeExtensions` prepares preinstalled VS Code extension payloads
- `compileTestPlan` builds the smoke test plan from top-level and enabled profile smoke cases
- `compileMetadata` renders Dev Containers metadata
- `compileFilesystem` creates generated root filesystem files
- `compileLayers` creates the semantic layer plan
- `compileImage` creates the nix2container image
- `compileReports` writes machine-readable build reports and owns the report entry registry

Each compiler returns both build artifacts and structured data. Later compilers receive the outputs they need rather than recomputing state. This keeps the flow inspectable and makes reports match the actual image.

Smoke plans expose stable case identity through `caseIds` and each test entry's `id`. Each test entry contains ordered `scripts`; each script has a shell command string, shell name, and interactive flag. Consumers should run scripts in order for a case and should not treat the `tests[]` array order as a public contract.

`compileReports` defines `baseReportEntries`, derives `ci-plan.json`
`reportFiles`, and links the reports directory from those same entries. Report
checks read `ci-plan.json` before validating files, so adding a report starts in
the report compiler rather than in a separate checker list.

## Runtime Filesystem Contract

All images share a single-user runtime contract:

- `User = "vscode"`
- uid/gid `1000`
- `HOME=/home/vscode`
- working directory `/workspaces`
- default command `sleep infinity`
- entrypoint `/usr/bin/devcontainer-entrypoint`

Generated filesystem content includes `/etc/passwd`, `/etc/group`, `/etc/os-release`, `/etc/xdg`, `/home/vscode`, `/tmp`, `/var/{cache,lib,log,tmp}`, `/run/user/1000`, and `/workspaces`. `/run/user/1000` is the fixed `XDG_RUNTIME_DIR`; it is owned by `vscode:vscode` and has mode `0700`. `/var/run` is a compatibility symlink to `/run`.

The image root follows a usr-merge layout. Nix package outputs are still collected from their native `/bin`, `/lib`, `/share`, and related output directories, then the generated root trees are normalized so the primary runtime locations are `/usr/bin`, `/usr/lib`, `/usr/lib64`, `/usr/libexec`, `/usr/include`, and `/usr/share`. Compatibility links keep `/bin`, `/sbin`, `/lib`, `/lib64`, `/libexec`, `/include`, and `/share` available. `/usr/local/{bin,etc,include,lib,lib64,sbin,share,src}` exists for local administrator or user overlays; image-provided Nix tools are not installed there. Package `/sbin` outputs are not linked into the image by default, so Nix glibc's `ldconfig` is not exposed as `/sbin/ldconfig`; VS Code's requirement check falls back to the explicit `/usr/lib/libc.so.6` and `/usr/lib/libstdc++.so.6` compatibility links instead of reading a missing Nix store `ld.so.cache`.

Project `devcontainer.json` files should not set `remoteUser`, `containerUser`, or `updateRemoteUserUID`. The image metadata already sets the supported values. The image entrypoint refuses to start as another user, and `devcontainer-image check` reports those overrides as errors.

This fixed-user design reduces the number of supported runtime states. It also keeps generated files, Nix profiles, VS Code extension projection, and helper scripts aligned on one home directory and one uid/gid pair.

## Environment Model

The project tracks two configured environment scopes plus generated compiler values:

- `environment.variables` becomes the container environment for the OCI image config and is also exported from generated shell startup files
- `devcontainer.remoteEnv` becomes VS Code Dev Containers metadata only
- FHS runtime and native-library compilers add generated container environment values

`lib/compiler/env.nix` merges configured values with generated values from the FHS runtime and native-library compiler. It also builds `PATH` from ordered path segments, records the origin of each value, expands simple `$VAR` references, and reports conflicts.

The distinction matters because Docker image environment variables, VS Code remote environment variables, and interactive shell variables are applied at different times by different tools.

Workspace-derived values are intentionally late-bound. The image compiler does
not expand `WORKSPACE` through a build-time or image-time
`DEVCONTAINER_WORKSPACE` value, and static image environment variables omit
workspace-derived entries. Generated Dev Containers metadata sets
`WORKSPACE=${containerWorkspaceFolder}`, and generated shell startup files use
that runtime value when appending project-local PATH entries or exporting values
such as `CARGO_TARGET_DIR`.

`PATH` is the most important edge case. The image config keeps only the
workspace-independent compiled `PATH` for non-VS Code processes and reports.
Generated Dev Containers metadata does not publish `containerEnv.PATH` by
default. VS Code injects its Remote CLI directory, such as
`/vscode/vscode-server/.../bin/remote-cli`, into the container process
environment after the image is built. If metadata or login shell startup files
re-export the compiled `PATH` as a plain static value, the injected `code`
command disappears from terminals. Generated shell startup files must merge the
inherited `PATH` first and append any missing compiled segments, rather than
replacing `PATH`.

## FHS Runtime

VS Code server components and many extension helpers expect conventional Linux paths that a pure Nix image does not naturally provide. When `devcontainer.compat.fhsRuntime.enable` is true, the FHS runtime adds a fixed compatibility surface needed for those tools:

- `/bin/bash`
- `/bin/sh`
- `/usr/bin/env`
- common archive and network tools through conventional `/usr/bin` paths
- architecture dynamic loader path such as `/lib64/ld-linux-x86-64.so.2`
- `NIX_LD` and `NIX_LD_LIBRARY_PATH` from `programs.nix-ld`
- `/usr/lib/libc.so.6`
- `/usr/lib/libstdc++.so.6`
- CA certificate files and environment variables from `security.pki`

The FHS runtime is compatibility glue. It does not expose per-path toggles, does not turn the image into a general FHS distribution, and modules should not treat it as a reason to bypass Nix store paths when a Nix-native path is available. `/etc/os-release` belongs to the generated filesystem contract and is present independently of the FHS runtime symlink set.

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

The generated filesystem includes `/etc/nix/nix.conf` from `nix.settings` and `/etc/nixpkgs/config.nix` with the same nixpkgs policy used by the image build. Container environment variables also set nixpkgs policy defaults and `DEVPKG_NIXPKGS_REF=path:<locked-nixpkgs-source>`, so runtime package installs follow the flake-locked nixpkgs input without fetching nixpkgs on first use. `DEVPKG_SYSTEM` and `DEVPKG_NIXPKGS_CACHE_KEY` give runtime helpers a stable completion-cache key without evaluating the system first. The image keeps that source reachable through `/usr/share/devcontainer/nixpkgs` and its `/nix/store/...-source` target. `devpkg` runs flake evaluation and installation commands with `--impure` so packages such as Google Chrome and Microsoft Edge can read those defaults.

The `devpkg` runtime package also ships Bash completion under `/usr/share/bash-completion/completions/devpkg` in the generated image. It completes subcommands, common options, installed profile entries, and nixpkgs package attributes from the same locked nixpkgs source. Package-attribute completion caches scope attrnames under `$XDG_CACHE_HOME/devpkg/packages`, keyed by nixpkgs cache key, system, and parent scope. Interactive shell startup only defines the completion function; nixpkgs evaluation happens on completion use and is skipped on cache hits.

## Runtime Helpers

Runtime helper metadata lives in `runtime/default.nix`. The helper registry
defines each helper package plus whether it is exposed as a public flake
package, installed into images, covered by a focused tool check, and where it
appears in the deterministic image-install order.

`flake.nix`, `lib/compiler/image.nix`, and `flake/checks/tooling.nix` consume
that metadata. Public packages, image installation, and check wiring should not
maintain separate helper lists.

## Locale, Shell, And Fonts

The default locale contract is:

- `LANG=en_US.UTF-8`
- `LANGUAGE=en_US:en`
- `LOCALE_ARCHIVE` from `pkgs.glibcLocales`
- no default `LC_ALL`

`LC_ALL` is intentionally unset because it overrides every locale category. Image modules can set specific `LC_*` variables through `i18n.extraLocaleSettings`.

Generated shell files are `/etc/profile`, `/etc/bashrc`, and `/etc/bash.bashrc`. Interactive Bash gets aliases, a lightweight prompt, history settings, bash completion, and a command-not-found handler. The handler only queries the local nix-index database after an unknown command is entered and returns 127. It does not install software, call the network, execute project commands, or perform nix-index work during shell startup.

XDG defaults are explicit and absolute in the container environment: `XDG_CONFIG_HOME=/home/vscode/.config`, `XDG_CACHE_HOME=/home/vscode/.cache`, `XDG_DATA_HOME=/home/vscode/.local/share`, `XDG_STATE_HOME=/home/vscode/.local/state`, `XDG_RUNTIME_DIR=/run/user/1000`, `XDG_CONFIG_DIRS=/etc/xdg`, and `XDG_DATA_DIRS=/usr/local/share:/usr/share`. `PATH` prefers project and user tools, then `/usr/local/bin:/usr/bin`; it does not include `/bin` because `/bin` is only the usr-merge compatibility symlink.

All images include fontconfig and Noto Latin, CJK, symbol, and emoji coverage. Fontconfig defaults prefer Simplified Chinese CJK families for generic sans, serif, and monospace aliases. See [Fonts And Fontconfig](fonts-fontconfig.md) for the detailed font design.

## VS Code Metadata And Extensions

The OCI image label `devcontainer.metadata` is a JSON array. It contains the computed Dev Containers metadata for users, environment, lifecycle commands, VS Code extension customizations, and the read-only workspace `.devcontainer` mount that prevents container-side edits to host-executed lifecycle configuration.

VS Code extension support has two parts:

- modules declare extension identifiers and settings
- the extension compiler prepares extension payloads and metadata for projection into VS Code server extension directories

VS Code extension artifacts are split by use. The default image includes only unpacked extension directories under `/usr/share/devcontainer/vscode/extensions`, which are the inputs needed by the projection lifecycle task. `.vsix` archives are omitted by default and can be added with the `"archive"` artifact mode when an image needs audit or reinstall payloads. When enabled, archives live under `/usr/share/devcontainer/vscode/vsix` and are placed in their own image layer.

`extensions-index.json` is the projector input and contains projection targets plus extension `id`, `path`, projection strategy, and whether the source is `required`. Required extension sources fail projection when missing; optional sources warn and are skipped. `extensions-report.json` is the audit surface and records source locks, artifact modes, projection/archive paths, required state, and validation metadata.

VS Code keeps two deliberate home-directory exceptions because the Remote Server looks there. Preinstalled extensions are projected into `/home/vscode/.vscode-server/extensions`, `/home/vscode/.vscode-server-insiders/extensions`, and `/home/vscode/.vscode-remote/extensions`. The same server roots also contain root-owned, read-only `data/Machine/settings.json` files generated from the compiled VS Code settings. These settings files are preformatted in the image so VS Code does not try to rewrite them during startup, which would fail because the files are intentionally read-only. Their server root, `data`, and `data/Machine` directories stay sticky-writable so VS Code can create its normal runtime content, while `settings.json` is not writable by the `vscode` user. Other shared image data lives under `/usr/share/devcontainer`. VS Code Remote Server logs show temporary socket handling as `VSC_TMP="${XDG_RUNTIME_DIR:-/tmp}"`; with `XDG_RUNTIME_DIR=/run/user/1000`, VS Code IPC sockets can use `/run/user/1000/vscode-ipc-*.sock` and only fall back to `/tmp` when the runtime directory is unset.

VS Code settings that need absolute tool paths point at the usr-merged locations: language servers and command tools use `/usr/bin`, TypeScript uses `/usr/lib/node_modules/typescript/lib`, and Go uses `/usr/share/go`. `/usr/local` is left for local overrides.

Lifecycle tasks are declared as structured Nix module values. The lifecycle compiler turns them into metadata commands that call `devcontainer-task-runner`, which gives the project one consistent place for task ordering, once-only behavior, timeouts, and user validation.

## Reports And Checks

Reports are part of the architecture, not just debug output. They make image composition visible without unpacking an OCI artifact.

Important reports include:

- profile reports
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
- layer closure reports
- smoke test plans
- CI plans

Checks use those reports to reject regressions before an image is published. Smoke tests then validate user-visible runtime behavior after an image is loaded into Docker. Standalone smoke execution creates containers with Docker `--network none`, so smoke cases should verify local image behavior without requiring internet access.

`flake/checks.nix` owns the Nix check set by aggregating:

- `contracts` for pure evaluation and static public contracts
- `tooling` for runtime helper behavior
- `artifacts` for selected OCI/rootfs checks
- `report-cli` for the report inspection CLI

Image-specific check policy belongs on target records in `images/default.nix`.
For example, target metadata marks required public image targets, required
report profiles/commands, and rootfs path requirements. The check modules derive
concrete check attributes from the image target list and metadata.

VS Code GUI E2E session metadata lives beside the tests in
`tests/e2e/vscode-gui.nix`. `sessionEntries` drives the exported `e2e` attrs and
the generated session table in [VS Code GUI E2E Testing](e2e-testing.md).

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

- user-facing image behavior usually belongs in a profile declared by a module
- shared generated files usually belong in a focused compiler
- runtime commands belong under `runtime/`
- repeated package groups should become profiles; profile graph nodes are generated automatically
- user-visible image behavior should declare an owner-local smoke case
- compiler behavior should have contract or report checks
- browser, font, or Docker daemon behavior should be documented because those areas have important runtime constraints

The goal is for every new behavior to appear in the module config, the graph, the image, and the reports in a way a maintainer can inspect.
