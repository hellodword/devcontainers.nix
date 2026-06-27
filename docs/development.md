# Development And Maintenance

This guide is for maintainers extending or changing this repository. Read [Architecture](architecture.md) first if the compiler flow is unfamiliar.

## Local Requirements

You need:

- Nix with flakes enabled
- an `x86_64-linux` build environment
- Docker only for loading images and running runtime smoke tests

The fast local loop is:

```sh
nix flake check
```

This runs contract checks, report CLI checks, selected image artifact checks, focused runtime helper suites, and generated workflow synchronization.

## Repository Map

Important paths:

| Path | Purpose |
| --- | --- |
| `flake.nix` | Pins inputs and assembles image outputs, packages, apps, checks, and library metadata. |
| `flake/` | Maintainer flake internals: image targets, checks, and workflow generation. |
| `images/` | Small image-family modules that combine shared modules. |
| `lib/modules/core/` | Shared image contract: options, user, filesystem, environment, shell, fonts, libraries, metadata, lifecycle, VS Code extensions, FHS runtime. |
| `lib/modules/programs/` | Static program integrations such as Git, SSH, and nix-index. |
| `lib/modules/toolsets/` | Reusable command groups such as source control, Docker client, data/network, and debug tools. |
| `lib/modules/runtimes/` | Shared language runtimes used by multiple image families. |
| `lib/modules/languages/` | Full language stacks such as Go, Python, Node.js, Rust, and Flutter. |
| `lib/compiler/` | Pure compiler stages that turn evaluated module config into image artifacts and reports. |
| `runtime/` | Shell helpers installed into images or exposed as package outputs. |
| `tests/ci/` | Report, artifact, and helper validation. |
| `tests/smoke/` | Runtime smoke execution after an image is loaded into Docker. |
| `tests/e2e/` | Heavy VS Code GUI Dev Containers tests. |
| `docs/` | User, design, and maintenance documentation. |

## Build And Inspect

Build reports for one image:

```sh
nix build .#images.nix.reports
```

Build the nix2container image artifact:

```sh
nix build .#images.nix.oci
```

Load an image into the local Docker daemon:

```sh
nix run .#load-nix
nix run .#load-python3
```

Build the generated font root or other compiler outputs through the `images.<name>` attr when debugging a specific compiler stage:

```sh
nix build .#images.nix.fonts.root --print-out-paths --no-link
```

Inspect reports through the packaged helper:

```sh
nix build .#images.nix.reports
report="$(readlink -f result)"
nix run .#devcontainer-image -- explain layer 0 --report "$report"
nix run .#devcontainer-image -- explain package bash --report "$report"
nix run .#devcontainer-image -- explain extension golang.go --report "$report"
nix run .#devcontainer-image -- explain env PATH --report "$report"
nix run .#devcontainer-image -- explain filesystem --report "$report"
nix run .#devcontainer-image -- explain image-plan --report "$report"
nix run .#devcontainer-image -- explain security --report "$report"
nix run .#devcontainer-image -- diff old-layer-plan.json "$report/layer-plan.json"
nix run .#devcontainer-image -- doctor image ghcr.io/hellodword/devcontainers-nix:latest
```

## Smoke Tests

After loading an image, run its smoke plan:

```sh
nix run .#run-smoke-plan -- nix
```

The smoke runner is exposed as a flake app so Python, Nix, and Docker CLI paths come from nixpkgs. It still talks to the host Docker daemon and writes logs to `${SMOKE_LOG_DIR:-smoke-logs}`. It never accepts extra Docker run arguments and does not inject Docker daemon configuration into the container. It validates image capabilities that are owned by this repository; Docker daemon endpoint configuration stays a project-level Dev Containers choice.

## Heavy VS Code GUI E2E

Real VS Code Dev Containers GUI tests are exposed under
`e2e.${system}.e2e-vscode-<image>-<session>`. They are intentionally not part
of `nix flake check`.

`e2e` is a custom flake output, so `nix flake check` can warn that `images` and
`e2e` are unknown outputs. That warning is an accepted tradeoff: the heavy GUI
E2E derivations remain opt-in and are not traversed by the default check path.

Read [VS Code GUI E2E Testing](e2e-testing.md) before changing
`tests/e2e/vscode-gui.nix`, desktop sessions, Command Palette automation,
timeouts, or GUI readiness detection.

## Adding Or Changing An Image

1. Add or update a module in `images/`.
2. Reuse existing core, runtime, toolset, and language modules before adding new ones.
3. Add the image target in `flake/targets.nix` with target name, family, tags, module, and any version override modules. Use the existing version-entry helpers when a family exposes latest and previous version targets.
4. Run `nix run .#generate-docs` when targets, families, tags, or published image references changed.
5. Update `contracts-image-targets` or another focused contract check when the public image contract changes.
6. Run `nix flake check`.
7. Build the image reports and inspect `profile-report.json`, `graph.json`, `layer-plan.json`, and `metadata-label.json`.
8. Load the image and run `nix run .#run-smoke-plan -- <target>` when runtime behavior changed.
9. Update [Usage](usage.md) if the published image contract changed beyond the generated image-reference snippet.

Use target names for local build outputs and smoke plans, for example `go`. Use family and tag for registry references, for example `ghcr.io/hellodword/devcontainers-go:latest`.

## Adding A Toolset

A toolset is a reusable group of packages that can be enabled by many images.

1. Add an option under `devcontainer.toolsets` in `lib/modules/core/options.nix`.
2. Add a module under `lib/modules/toolsets/`.
3. Load the module from `lib/compiler/eval.nix`.
4. Define a `devcontainer.profiles."toolset/<name>"` leaf profile with packages, provided commands, environment fragments, VS Code metadata, lifecycle tasks, library presets, and smoke capabilities as needed.
5. Use a stable layer bucket in the profile `group`.
6. Add a capability in `lib/tests/smoke-catalog.nix` for important user-visible commands.
7. Enable the profile from image modules or bundle profiles that need it.
8. Run report checks and inspect profile, graph, and layer reports.

Keep toolsets focused. A package belongs in a toolset when it is useful across multiple image families. If it only makes sense for one language, put it in that language module instead.

## Adding A Static Program Module

Use `lib/modules/programs/` for static program integrations that need generated `/etc` files or shell hooks.

Allowed NixOS-like surfaces are the static subset documented in [Architecture](architecture.md): `programs.git`, `programs.ssh`, `programs.nix-index`, `programs.nix-ld`, `programs.bash`, `environment.*`, `i18n.*`, `time.*`, `security.pki.*`, and `nix.settings`.

Do not add NixOS APIs that imply runtime service management, privilege elevation, PAM, polkit, sudo, setuid wrappers, multi-user state, or a Docker daemon. Unknown `services.*`, `users.users`, `users.groups`, and `virtualisation.docker.enable` usage should stay unsupported.

When adding a program module:

1. Add typed options in `lib/modules/core/options.nix`.
2. Add the renderer under `lib/modules/programs/`.
3. Generate files through `environment.etc`.
4. Add packages through `environment.systemPackages`.
5. Add shell integration through `environment.shellInit` or `environment.interactiveShellInit` only when it has no network, installer, or long-running side effects.
6. Add report assertions in `tests/ci/check-reports.py` or a focused contract check under `flake/checks/`.

## Adding A Language Or Runtime

Use a runtime module when multiple language stacks need a base runtime. Use a language module when it represents the developer-facing stack for one language.

1. Add options in `lib/modules/core/options.nix`.
2. Add a runtime module under `lib/modules/runtimes/` or a language module under `lib/modules/languages/`.
3. Load it from `lib/compiler/eval.nix`.
4. Define one or more `devcontainer.profiles` leaf profiles for packages, environment variables, path segments, VS Code extensions, settings, aliases, library presets, lifecycle tasks, and capability declarations.
5. Define a bundle profile only when a named stack should enable multiple leaf profiles without owning resources itself.
6. Add a capability in `lib/tests/smoke-catalog.nix` when the module exposes user-visible behavior that should run in a real container.
7. Add image target wiring in `flake/targets.nix` if the language has version-specific tags.
8. Run `nix run .#generate-docs` if image targets, families, or tags changed.
9. Update [Usage](usage.md) with user-facing `devcontainer.json` examples when behavior changed beyond the generated reference table.

Version-specific language packages should be discovered from nixpkgs or the relevant overlay in `flake/targets.nix`, then injected through small override modules following the Go, Node.js, Python, and Rust patterns.

## Adding Compiler Behavior

Compiler changes belong under `lib/compiler/`.

1. Add a focused compiler or extend the existing compiler that owns the behavior.
2. Return structured data as well as build artifacts.
3. Thread the compiler output through `lib/default.nix`.
4. Include generated files in `compileFilesystem` or `compileImage` only at the stage that owns them.
5. Add report output in `compileReports`.
6. Add report validation in `tests/ci/check-reports.py` or an adjacent check.
7. Update [Architecture](architecture.md) when the pipeline or ownership model changes.

Avoid hidden side effects. If a behavior changes the image, it should be visible in reports, a compiler contract, or a capability smoke test.

Do not add direct `devcontainer.graph.nodes` entries for ordinary package groups. New language stacks, toolsets, editor integrations, and small reusable tools should define profiles and let `compileProfiles` create graph nodes. Direct graph nodes are for compiler-owned or core generated content such as FHS compatibility, fonts, shell files, filesystem roots, and dynamic library profiles.

## Adding Runtime Helpers

Runtime helpers live in `runtime/` and are packaged by `runtime/default.nix`.

When changing a helper:

1. Keep the helper runnable outside the image when possible.
2. Add or update the focused helper suite in `tests/ci/check-devpkg.py`, `tests/ci/check-task-runner.py`, `tests/ci/check-vscode-extension-projector.py`, or `tests/ci/check-gui-env.py`.
3. If the helper is installed into the image, confirm the image compiler includes it in the runtime root or generated filesystem.
4. Document user-visible commands in [Usage](usage.md).

Examples:

- `devpkg` manages ad-hoc user packages and dynamic native-library profiles.
- `devcontainer-image` validates metadata labels or project devcontainer JSON.
- `devcontainer-task-runner` runs structured lifecycle tasks.
- `vscode-extension-projector` projects preinstalled VS Code extensions into server extension directories.

## Native Libraries

Native-library behavior spans modules, compiler code, runtime helper behavior, reports, and smoke tests.

When changing it, check:

- `lib/modules/core/options.nix`
- `lib/modules/core/libraries.nix`
- `lib/compiler/libraries.nix`
- `runtime/devpkg/main.py`
- the focused helper suite under `tests/ci/check-*.py`
- `tests/ci/check-reports.py`
- `docs/usage.md`
- `docs/architecture.md`

Keep runtime libraries and build libraries separate. Runtime libraries feed dynamic loading. Build libraries also expose headers, `pkg-config`, CMake prefixes, and compiler flags.

## Translating Devbox Or Devshell Snippets

Devbox and devshell configuration can inform an image module, but there is no converter and no compatibility promise.

Manual mapping guidelines:

- Devbox `packages` and devshell `packages` usually map to `environment.systemPackages`.
- Devbox `env` and devshell `env` usually map to `environment.variables` after reviewing whether values should be baked into the image.
- Devbox `shell.scripts` and `init_hook`, and devshell `commands`, usually map to documented project commands, smoke tests, or lifecycle tasks only after reviewing side effects.

Do not bake secrets, proxy credentials, or machine-specific paths into image modules. Prefer project `devcontainer.json` runtime environment for per-user or per-project values.

## Fonts

Font behavior has a dedicated design and maintenance document: [Fonts And Fontconfig](fonts-fontconfig.md).

Use that document when changing default font packages, fallback order, fontconfig generation, cache policy, reports, or smoke expectations.

## GitHub Actions

Image workflows are generated one file per image:

```sh
nix run .#generate-workflows
```

The generator renders `.github/workflows/_build-image.yml.j2` with minijinja and writes complete `build-image-*.yml` workflows.

One workflow per image is intentional. Image builds do not use a matrix workflow because matrix jobs and GitHub Actions concurrency have an observed failure mode where unfinished matrix jobs can be canceled before the image set completes. Separate workflows give each image target its own concurrency group and limit cancellation to that target.

`flake/workflows.nix` also defines the generated workflow sync check:

```sh
nix build .#checks.x86_64-linux.generated-workflows
```

The checked-in generated workflows, template, and target list should remain synchronized.

The workflows do not use GitHub Actions cache. Nix already uses configured binary substituters for reusable store paths, while per-run image closures and Docker artifacts are large and input-sensitive.

The `Free disk space` step removes large preinstalled SDKs and prunes Docker state because hosted Ubuntu runners have limited writable disk.

## Documentation Rules

Keep documentation split by audience:

- `README.md` is only overview, quick start, and navigation.
- `docs/usage.md` is for users writing `devcontainer.json`.
- `docs/architecture.md` is for understanding the design.
- `docs/development.md` is for maintainers extending the project.
- specialized design notes stay in their focused documents.

When changing a feature, update the smallest relevant set of docs. User-visible image behavior belongs in usage docs. Compiler ownership or invariants belong in architecture docs. Maintenance checklists belong in development docs or focused subsystem docs.

Generated snippets are deliberately limited to target-derived image reference tables:

```sh
nix run .#generate-docs
```

The generator updates only marked blocks in `README.md`, `docs/usage.md`, and
`docs/architecture.md`. There is no documentation consistency check; run the
generator as part of target, family, and tag changes.
