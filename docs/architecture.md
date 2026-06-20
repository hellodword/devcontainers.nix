# Architecture

This project compiles declarative image modules into nix2container OCI images for `x86_64-linux`.

## Inputs

The flake pins:

- `nixpkgs` on `github:NixOS/nixpkgs/nixos-unstable`
- `rust-overlay`
- `nix-vscode-extensions`
- `nix-index-database`
- `llm-agents`
- `nix2container`

## Compiler Flow

1. Nix modules evaluate `devcontainer.*` options.
2. The graph compiler groups package nodes into semantic buckets.
3. The layer compiler emits a reportable layer plan.
4. The image compiler builds explicit nix2container layers from those buckets.
5. A final customization layer adds runtime helpers, generated filesystem files, VS Code metadata, extension payloads, and FHS symlinks.

The compiler only uses nix2container for OCI image generation.

## Layer Strategy

OCI runtimes have practical layer-count limits, and devcontainer images accumulate many language runtimes, tools, extensions, and generated files. This project keeps layer construction deterministic and bounded:

- Module authors assign graph nodes to semantic buckets such as base runtime, FHS runtime, language tooling, VS Code extensions, and dynamic package runtime.
- The layer compiler emits `layer-plan.json` with the configured budget, defaulting to a maximum of 100 semantic buckets with 20 reserved slots.
- Each semantic bucket is built as a single explicit nix2container layer (`maxLayers = 1`) so related paths stay together and reports remain reviewable.
- The final customization layer uses `maxLayers = 4` for runtime helpers, metadata, generated filesystem files, and the Nix database.
- Previously built semantic layers are passed explicitly. Their transitive `nestedLayers` metadata is cleared in the compiler so nix2container does not expand duplicate parent layers into oversized arguments.

CI checks reject layer plans that exceed the configured budget.

## VS Code FHS Runtime

VS Code server components and common extension helpers expect several conventional Linux paths that are not normally present in a pure Nix image. The FHS runtime provides only the compatibility surface required for those tools:

- `/bin/bash`, `/bin/sh`, `/usr/bin/env`, and common archive/network tools point at Nix-provided binaries.
- The architecture dynamic loader path, for example `/lib64/ld-linux-x86-64.so.2`, points at `nix-ld`.
- `NIX_LD` points at the real glibc loader and `NIX_LD_LIBRARY_PATH` includes glibc plus the GCC runtime libraries.
- `/usr/lib/libc.so.6` and `/usr/lib/libstdc++.so.6` expose the glibc and GCC runtime libraries for tools that probe conventional library paths.
- CA bundle environment variables point at `/etc/ssl/certs/ca-certificates.crt`.

The FHS layer is compatibility glue for VS Code and extension tooling. It does not turn the image into a general FHS distribution.

## Nix Database

Images enable nix2container's `initializeNixDatabase` support. The generated Nix database registers the store paths already present in the image, makes `/nix`, `/nix/store`, and `/nix/var/nix` writable by the container user, and avoids a separate registration workaround at startup.

This is required for `devpkg`, which installs ad-hoc user packages with `nix profile add`. Without the database, Nix can see paths on disk that are not registered in `/nix/var/nix/db`, causing profile installs to fail or to reference missing store paths.

The generated filesystem layer intentionally does not create `/nix` paths. `/nix` ownership and database contents are owned by the nix2container database layer to avoid tar path collisions.

## Runtime Contract

Images set:

- `User = "vscode"`
- `WorkingDir = "/workspaces"`
- `HOME=/home/vscode`
- entrypoint `/usr/local/bin/devcontainer-entrypoint`
- default command `sleep infinity`

Generated filesystem content includes `/etc/passwd`, `/etc/group`, `/etc/os-release`, `/home/vscode`, `/tmp`, `/var/tmp`, `/run/user/1000`, and `/workspaces`.

## Metadata

The image label `devcontainer.metadata` is a JSON array. It includes remote/container user settings, container and remote environment, lifecycle commands, and VS Code customizations.
