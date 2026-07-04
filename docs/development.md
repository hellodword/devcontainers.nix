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

| Path                     | Purpose                                                                                                                    |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| `flake.nix`              | Pins inputs and assembles image outputs, packages, apps, checks, and library metadata.                                     |
| `flake/`                 | Maintainer flake internals: docs, checks, workflow generation, and E2E output wiring.                                      |
| `images/`                | Image target registry plus small image-family modules that combine shared modules.                                         |
| `lib/modules/core/`      | Shared image contract: user, filesystem, environment, shell, fonts, libraries, metadata, lifecycle, PATH, and FHS runtime. |
| `lib/modules/editor/`    | Editor integrations, shared editor bundles, VS Code extension metadata, and editor-focused smoke coverage.                 |
| `lib/modules/programs/`  | Static program integrations such as Git, SSH, and nix-index.                                                               |
| `lib/modules/toolsets/`  | Reusable command groups such as source control, Docker client, data/network, and debug tools.                              |
| `lib/modules/tools/`     | Small standalone tools that are useful globally but do not justify a larger toolset.                                       |
| `lib/modules/runtimes/`  | Shared language runtimes used by multiple image families.                                                                  |
| `lib/modules/languages/` | Full language stacks such as Go, Python, Node.js, Rust, and Flutter.                                                       |
| `lib/compiler/`          | Pure compiler stages that turn evaluated module config into image artifacts and reports.                                   |
| `runtime/`               | Shell helpers installed into images or exposed as package outputs.                                                         |
| `tests/ci/`              | Report, artifact, and helper validation.                                                                                   |
| `tests/smoke/`           | Runtime smoke execution after an image is loaded into Docker.                                                              |
| `tests/e2e/`             | Heavy VS Code GUI Dev Containers tests.                                                                                    |
| `docs/`                  | User, design, and maintenance documentation.                                                                               |

## Maintenance Registries

Keep source-of-truth metadata near the owner:

- Image target identity, generated target docs, workflow E2E opt-in, and image-specific check policy live in `images/default.nix`.
- Report file entries live in `lib/compiler/reports.nix` as `baseReportEntries` and `reportEntries`; `ci-plan.json` and report checks derive from them.
- Runtime helper metadata lives in `runtime/default.nix`; public package exposure, image installation, and focused helper checks derive from it.
- VS Code GUI E2E session metadata lives in `tests/e2e/vscode-gui.nix`; exported E2E attrs and generated docs derive from `sessionEntries`.
- Module loading derives from `lib/modules/default.nix`. New ordinary `.nix` files under a module category are picked up automatically.
- Layer and PATH bucket order derives from owner-local `devcontainer.layers.bucketDefinitions` and `devcontainer.path.bucketDefinitions`.

`flake/docs.nix`, `flake/workflows.nix`, and check modules consume these
registries. Do not add parallel image, report, helper, or session lists there
unless the new list is an explicit policy guard.

## Build And Inspect

Build reports for one image:

```sh
nix build .#images.nix.reports
```

Build the checked nix2container image artifact:

```sh
nix build .#images.nix.oci
```

This output depends on the layer budget gate. Inspect `layer-plan.json` for
planned semantic buckets and `layer-closure-report.json` for real NAR closure
sizes. The hard registry-facing limit is checked against final OCI layer sizes
from the nix2container image JSON.

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

The smoke runner is exposed as a flake app so Python, Nix, and Docker CLI paths come from nixpkgs. It still talks to the host Docker daemon and writes logs to `${SMOKE_LOG_DIR:-smoke-logs}`. It creates each smoke container with Docker `--network none`, never accepts extra Docker run arguments, and does not inject Docker daemon configuration into the container. It validates repository-owned smoke cases; Docker daemon endpoint configuration stays a project-level Dev Containers choice.

`smoke-test-plan.json` publishes case identity through `caseIds` and each `tests[]` entry's `id`. Each test has a non-empty ordered `scripts` array with `command`, `shell`, and `interactive` fields. Smoke cases should be offline safe. The smoke runner creates one temporary container per case and runs that case's scripts sequentially in the same container, using `timeoutSeconds` as the whole-case budget. The order of `tests[]` is not a public contract; compare smoke plan contents by sorting entries by `id`.

The `fhs.ca-certificates` smoke case verifies the local CA bundle path, CA-related environment variables, and PEM bundle contents. It does not verify external TLS connectivity.

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

When adding a GUI E2E session, add it to `sessionEntries` in
`tests/e2e/vscode-gui.nix` with backend, desktop docs, launch flags, readiness
logic, and NixOS module data. Then run `nix run .#generate-docs` so the session
table in [VS Code GUI E2E Testing](e2e-testing.md) stays derived from the
registry.

## Placement Decision Guide

When adding content, choose the owner by reuse and responsibility:

| Level             | Use when                                                                                                                                                             | Do not use for                                                                                          |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `image` module    | Assembling a published image from existing profiles, image name/tag policy, version overrides, and image-specific checks.                                            | Owning ordinary packages, VS Code extensions, env vars, or libraries directly.                          |
| bundle profile    | Naming a stack made from other profiles, such as a web bundle.                                                                                                       | Packages, env vars, VS Code metadata, lifecycle tasks, or smoke cases. Bundles must stay resource-free. |
| leaf profile      | Owning actual image content: packages, provided commands, VS Code extensions/settings, env vars, PATH entries, lifecycle tasks, library presets, and smoke cases.    | Merely grouping other profiles.                                                                         |
| `language` module | Developer-facing support for one language: language server, formatter, debugger, language extension, language env, and language smoke.                               | Shared interpreters or generic tools used by many languages.                                            |
| `runtime` module  | A shared runtime substrate used by multiple language stacks, such as Python, Node.js, C/C++ build environment, or Android runtime pieces.                            | Language-specific linters, formatters, or editor choices.                                               |
| `toolset` module  | A reusable group of cross-language tools, such as source control, Docker client tools, search/navigation, or network/data tools.                                     | One-off tools that only support one language.                                                           |
| `tool` module     | A small standalone tool or editor helper that is useful globally and does not justify a larger toolset.                                                              | Tool groups with multiple related commands.                                                             |
| `program` module  | Static system-style integrations with NixOS-like options, generated `/etc` files, shell hooks, or policy such as Git, SSH, or nix-index.                             | Runtime services, privilege management, Docker daemon setup, or ordinary package bundles.               |
| `core` module     | Global image invariants and compiler-backed surfaces: fixed user, filesystem layout, environment model, PATH buckets, FHS runtime, libraries, fonts, security roots. | Feature work that can live in a profile, language, runtime, toolset, tool, or program module.           |

Default to an existing leaf profile in the module that already owns the
behavior. Create a new leaf profile only when the addition has its own enable
boundary, layer bucket, smoke case, or reuse story. Create a bundle only to
activate multiple existing leaf profiles together.

Choose a module by behavior ownership first, then define any
`devcontainer.profiles` entries in that owner module. Do not create a separate
module location merely because the declaration is a profile.

## Small Existing Module Edits

For small additions, edit the profile that already owns the behavior and keep
reports/smoke coverage aligned.

### Add A VS Code Extension

Add the extension under the owning leaf profile's `vscode.extensions`:

```nix
vscode.extensions."publisher.extension-id" = {
  native = false;
  required = true;
  bucket = "vscode-extensions-python";
  companionTools = [ "python" ];
};
```

Use the module's existing VS Code extension bucket. If none exists, add an
owner-local `devcontainer.layers.bucketDefinitions."vscode-extensions-<owner>"`
entry in the same module and use that bucket. Set `companionTools` to commands
the extension expects from the image. Leave `required = true` for normal
preinstalled extensions; set it to `false` only when a missing projection source
should warn and skip instead of failing container lifecycle setup. Use `notes`
when the extension is syntax only or intentionally has no companion tool.

Update a focused compiler contract or report assertion when the extension
changes ownership, bucket placement, companion-tool policy, or published image
extension metadata.
Run `nix flake check` so duplicate extension ownership, companion-tool
validation, extension artifact locking, and generated report checks run.
For affected images, inspect `profile-report.json`, `extensions-report.json`,
and the projector-only `extensions-index.json`.

### Add An Executable

Add the package to the owning profile's package list and record the command in
`provides.commands`:

```nix
packages = packages ++ [ pkgs.example-tool ];
provides.commands = [
  "existing-tool"
  "example-tool"
];
```

Add or update a smoke case when the command is user-visible:

```nix
tests.cases."language.example" = {
  tags = [
    "smoke"
    "language"
    "example"
  ];
  scripts = [
    {
      shell = "bash";
      interactive = false;
      command = "example-tool --version";
    }
  ];
};
```

If the executable is a generated project helper rather than a nixpkgs package,
put it under `runtime/`, register it in `runtime/default.nix`, and follow
[Adding Runtime Helpers](#adding-runtime-helpers).

Update report assertions or compiler contracts when the executable changes
profile ownership, provided command metadata, layer membership, PATH behavior,
or smoke case identity. Run `nix flake check`; load an affected image and run
`nix run .#run-smoke-plan -- <target>` when command behavior changed.

### Add A Native Library

Use `devcontainer.libraries.runtime` for shared objects needed at execution
time:

```nix
devcontainer.libraries.runtime = [ pkgs.libGL ];
```

Use `devcontainer.libraries.build` for headers, `pkg-config`, CMake prefixes,
compiler wrapper flags, and runtime outputs needed by builds:

```nix
devcontainer.libraries.build = [
  pkgs.openssl
  pkgs.zlib
];
```

Do not put native libraries in `profile.packages` unless users need commands
from those packages on `PATH`. Use `libraries.presets` only for language-level
integration behavior such as `cgo` or `rust-bindgen`.

Add or update a smoke case when the library affects a user-visible runtime or
build path. Update report assertions when library buckets, dynamic-linker
inputs, or library presets change.
Run `nix flake check`; for affected images, inspect `libraries-report.json`,
`env-report.json`, `fhs-runtime-report.json`, `closure-report.json`, and
`layer-closure-report.json`.

### Add An Environment Variable

Add stable container-wide variables to the owning leaf profile's
`env.variables`:

```nix
env.variables = {
  EXAMPLE_HOME = "$XDG_DATA_HOME/example";
};
```

Add VS Code-only variables to `env.remoteVariables`:

```nix
env.remoteVariables = {
  EXAMPLE_REMOTE = "1";
};
```

Use `env.path` for PATH additions and keep paths expressed with existing XDG or
tool-specific variables:

```nix
env = {
  variables.EXAMPLE_BIN = "$XDG_DATA_HOME/example/bin";
  path = [ "$EXAMPLE_BIN" ];
};
```

Update the profile's smoke case when the variable changes runtime behavior.
Update report assertions when the variable is part of a public image contract
or changes environment merge behavior.
Run `nix flake check`; for affected images, inspect `env-report.json`,
`metadata-label.json`, `metadata-merged-preview.json`, and shell reports when
shell initialization changed.

## Adding Or Changing An Image

1. Add or update a module in `images/`.
2. Reuse existing core, runtime, toolset, and language modules before adding new ones.
3. Add the image target in `images/default.nix` with target name, family, tags, module, `docs.useWhen`, and any version override modules. Use the existing version-entry helpers when a family exposes latest and previous version targets.
4. Set target metadata for policy that belongs to the image: `ci.e2eSessions` for workflow GUI E2E coverage and `checks` for required public targets, required report profiles/commands, or rootfs path requirements.
5. Run `nix run .#generate-docs` when targets, families, tags, generated docs text, or published image references changed.
6. Run `nix run .#generate-workflows` when image targets, target names, `ci.e2eSessions`, or workflow templates changed.
7. Update `contracts-image-targets` or another focused contract check when the public image contract changes.
8. Run `nix flake check`, including the generated workflow synchronization check.
9. Build the image reports and inspect `profile-report.json`, `graph.json`, `layer-plan.json`, and `metadata-label.json`.
10. Load the image and run `nix run .#run-smoke-plan -- <target>` when runtime behavior changed.
11. Update [Usage](usage.md) if the published image contract changed.

Use target names for local build outputs and smoke plans, for example `go`. Use family and tag for registry references, for example `ghcr.io/hellodword/devcontainers-go:latest`.

## Adding A Toolset

A toolset is a reusable group of packages that can be enabled by many images.

1. Add a module under `lib/modules/toolsets/`.
2. Define any typed `devcontainer.toolsets.<name>` options in that owner module.
3. Define a `devcontainer.profiles."toolset/<name>"` leaf profile with packages, provided commands, environment fragments, VS Code metadata, lifecycle tasks, library presets, and smoke cases as needed.
4. Declare a `devcontainer.layers.bucketDefinitions."<bucket>"` entry in the owning module when the profile needs a new stable layer bucket.
5. Use that stable layer bucket in the profile `group`.
6. Declare important user-visible command checks in the same profile's `tests.cases`.
7. Enable the profile from image modules or bundle profiles that need it.
8. Update report assertions or compiler contracts when the toolset changes profile ownership, layer buckets, VS Code metadata, env, lifecycle tasks, or smoke case identity.
9. Run `nix flake check`, then build reports for an affected image and inspect `profile-report.json`, `graph.json`, `layer-plan.json`, and `smoke-test-plan.json`.
10. Load an affected image and run `nix run .#run-smoke-plan -- <target>` when command behavior changed.

Layer bucket names should be semantic names such as `source-control-tools`.
Pick the bucket `order` from the semantic range documented in
[Architecture](architecture.md), use `100`-step spacing for new ordinary
buckets, and use `10`-step spacing only when inserting between adjacent existing
buckets.

When a composite bundle needs a smoke case for the combined behavior, add a zero-package smoke-only leaf profile such as `toolset/<name>/smoke` and include it from the bundle. Do not inject top-level `devcontainer.tests.cases` from non-core modules.

Keep toolsets focused. A package belongs in a toolset when it is useful across multiple image families. If it only makes sense for one language, put it in that language module instead.

## Adding A Static Program Module

Use `lib/modules/programs/` for static program integrations that need generated `/etc` files or shell hooks.

Allowed NixOS-like surfaces are the static subset documented in [Architecture](architecture.md): `programs.git`, `programs.ssh`, `programs.nix-index`, `programs.nix-ld`, `programs.bash`, `environment.*`, `i18n.*`, `time.*`, `security.pki.*`, and `nix.settings`.

Do not add NixOS APIs that imply runtime service management, privilege elevation, PAM, polkit, sudo, setuid wrappers, multi-user state, or a Docker daemon. Unknown `services.*`, `users.users`, `users.groups`, and `virtualisation.docker.enable` usage should stay unsupported.

When adding a program module:

1. Add the renderer under `lib/modules/programs/`.
2. Define typed `programs.<name>` options in that same owner module.
3. Generate files through `environment.etc`.
4. Add packages through `environment.systemPackages`.
5. Add shell integration through `environment.shellInit` or `environment.interactiveShellInit` only when it has no network, installer, or long-running side effects.
6. Add focused report assertions in `tests/ci/check-reports.py` or a contract check under `flake/checks/` when the generated report schema changes.
7. Add or update a smoke case when the module exposes user-visible commands, shell behavior, generated files, or environment behavior.
8. Update [Architecture](architecture.md) when the supported NixOS-like API subset or program ownership model changes.
9. Run `nix flake check`; load an affected image and run `nix run .#run-smoke-plan -- <target>` when runtime behavior changed.

## Adding A Language Or Runtime

Use a runtime module when multiple language stacks need a base runtime. Use a language module when it represents the developer-facing stack for one language.

1. Add a runtime module under `lib/modules/runtimes/` or a language module under `lib/modules/languages/`.
2. Define any typed package override options in that owner module.
3. Define one or more `devcontainer.profiles` leaf profiles for packages, environment variables, path segments, VS Code extensions, settings, aliases, library presets, lifecycle tasks, and smoke cases.
4. Declare owner-local `devcontainer.layers.bucketDefinitions` entries for new profile groups or VS Code extension buckets.
5. Define a bundle profile only when a named stack should enable multiple leaf profiles without owning resources itself.
6. Add a `tests.cases` entry next to the profile or owner module when the module exposes user-visible behavior that should run in a real container.
7. Add image target wiring in `images/default.nix` if the language has version-specific tags.
8. Run `nix run .#generate-docs` if image targets, families, tags, generated target docs, or published image references changed.
9. Run `nix run .#generate-workflows` if image targets, target names, target `ci.e2eSessions`, or workflow templates changed.
10. Update report assertions or compiler contracts when profile ownership, layer buckets, extension metadata, companion tools, PATH/env behavior, lifecycle tasks, or smoke case identity changes.
11. Run `nix flake check`; load an affected image and run `nix run .#run-smoke-plan -- <target>` when runtime behavior changed.
12. Update [Usage](usage.md) with user-facing `devcontainer.json` examples when behavior changed.

Layer bucket names should be semantic names such as `python-language` or
`vscode-extensions-python`. Choose new bucket `order` values from the semantic
ranges documented in [Architecture](architecture.md), using `100`-step spacing
for ordinary additions and `10`-step spacing for deliberate insertions.
`profile.priority` is a repeatable ordering tier within a bucket and is not a
global bucket slot.

When a bundle language profile needs a smoke case for the assembled stack, add a zero-package smoke-only leaf profile such as `language/<name>/smoke` and include it from the bundle. Keep top-level `devcontainer.tests.cases` for core-owned behavior only.

Version-specific language packages should be discovered from nixpkgs or the relevant overlay in `images/default.nix`, then injected through small override modules following the Go, Node.js, Python, and Rust patterns.

## Adding Compiler Behavior

Compiler changes belong under `lib/compiler/`.

1. Add a focused compiler or extend the existing compiler that owns the behavior.
2. Return structured data as well as build artifacts.
3. Thread the compiler output through `lib/default.nix`.
4. Include generated files in `compileFilesystem` or `compileImage` only at the stage that owns them.
5. Add report output in `compileReports`, including a `baseReportEntries` or `reportEntries` entry when it should appear in the reports link farm.
6. Add report validation in `tests/ci/check-reports.py` or an adjacent check; do not add a separate required-file list for reports already declared in `compileReports`.
7. Add or update focused compiler contract checks under `flake/checks/contracts/` when evaluation rules, validation errors, generated metadata, graph nodes, filesystem entries, lifecycle wiring, or public report shape changes.
8. Update report CLI tests or examples when `devcontainer-image explain`, `diff`, or `doctor` behavior changes.
9. Update [Architecture](architecture.md) when the pipeline or ownership model changes.
10. Run `nix flake check`.

Smoke cases use this shape:

```nix
tests.cases."language.example" = {
  tags = [
    "smoke"
    "language"
    "example"
  ];
  scripts = [
    {
      shell = "bash";
      interactive = false;
      command = "example-tool --version";
    }
  ];
};
```

Avoid hidden side effects. If a behavior changes the image, it should be visible in reports, a compiler contract, or a smoke case.

Do not add direct `devcontainer.graph.nodes` entries for ordinary package groups. New language stacks, toolsets, editor integrations, and small reusable tools should define profiles and let `compileProfiles` create graph nodes. Direct graph nodes are for compiler-owned or core generated content such as FHS compatibility, fonts, shell files, filesystem roots, and dynamic library profiles.

## Adding Runtime Helpers

Runtime helpers live in `runtime/` and are packaged by `runtime/default.nix`.
The `helperDefs` registry is the source of truth for public package exposure,
image installation order, and focused helper checks.

When changing a helper:

1. Keep the helper runnable outside the image when possible.
2. Add or update its `helperDefs` metadata: `order`, `publicPackage`, `installInImage`, and optional `checkName`, `checkScript`, and `checkEnvName`.
3. Add or update the focused helper suite in `tests/ci/check-devpkg.py`, `tests/ci/check-task-runner.py`, `tests/ci/check-vscode-extension-projector.py`, or `tests/ci/check-gui-env.py`.
4. Confirm derived wiring by checking the public flake package, image runtime root, and `tool-*` check when those metadata flags apply.
5. Add or update report assertions when helper installation, runtime root layout, lifecycle behavior, or helper metadata appears in reports.
6. Add or update smoke coverage when the helper changes in-image user-visible behavior.
7. Run `nix flake check`; run the focused `tool-*` check directly when iterating on one helper.
8. Document user-visible commands in [Usage](usage.md).

Examples:

- `devpkg` manages ad-hoc user packages and dynamic native-library profiles.
- `devcontainer-image` validates metadata labels or project devcontainer JSON.
- `devcontainer-task-runner` runs structured lifecycle tasks.
- `vscode-extension-projector` projects preinstalled VS Code extensions into server extension directories.

## Adding Reports

Reports are declared in `lib/compiler/reports.nix`.

1. Create the report JSON derivation from compiler-owned structured data.
2. Add it to `baseReportEntries` when it should be part of the report directory and `ci-plan.json` `reportFiles`.
3. Set `includeInCiPlan = false` only for internal or compatibility files that should be linked but not required by CI report validation.
4. Update `tests/ci/check-reports.py` for schema/content assertions. It reads the report file list from `ci-plan.json`.
5. Update report CLI tests or examples when the new report should be accepted by `devcontainer-image explain`, `diff`, or `doctor`.
6. Update [Architecture](architecture.md) or a focused subsystem document when the report changes maintainer-visible workflow.
7. Run `nix flake check`.

## Native Libraries

Native-library behavior spans modules, compiler code, runtime helper behavior, reports, and smoke tests.

When changing it, check:

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

The checked-in generated workflows, template, and target registry should remain synchronized.

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

Generated snippets are deliberately limited to target-derived image reference
tables and E2E session metadata:

```sh
nix run .#generate-docs
```

The generator updates only marked blocks in `README.md`,
`docs/architecture.md`, and `docs/e2e-testing.md`. There is no documentation
consistency check; run the generator as part of target, family, tag, target docs,
or E2E session changes.
