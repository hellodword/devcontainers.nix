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

The top-level `pkgs` fixpoint imports nixpkgs with a shared config:
`allowUnfree = true`, `android_sdk.accept_license = true`,
`oraclejdk.accept_license = true`, and `allowUnsupportedSystem = true`.
Inputs that expose package sets are consumed through overlays, so compiler
modules use `pkgs.*` rather than `inputs.foo.packages.*`. Local package
overrides should be added to the flake's `projectOverlays` list so image
builds, checks, and runtime helper packages see the same overridden drv.

## Compiler Flow

1. Nix modules evaluate `devcontainer.*` options.
2. The graph compiler groups package nodes into semantic buckets.
3. The layer compiler emits a reportable layer plan.
4. The image compiler builds explicit nix2container layers from those buckets.
5. A final customization layer adds runtime helpers, generated filesystem files, VS Code metadata, extension payloads, and FHS symlinks.

The compiler only uses nix2container for OCI image generation.

## Layer Strategy

OCI runtimes have practical layer-count limits, and GitHub Container Registry rejects oversized layer blobs. Devcontainer images accumulate many language runtimes, tools, extensions, and generated files, so this project keeps layer construction deterministic and bounded:

- Module authors assign graph nodes to semantic buckets such as base runtime, FHS runtime, language tooling, VS Code extensions, and dynamic package runtime.
- The layer compiler emits `layer-plan.json` with the configured budget, defaulting to a maximum of 100 semantic buckets with 20 reserved slots.
- GitHub Container Registry documents a 10 GB per-layer limit and a 10 minute upload timeout. The project uses `devcontainer.layers.maxLayerSize = "8GiB"` as the default safety line.
- Each semantic bucket is built as a single explicit nix2container layer (`maxLayers = 1`) so related paths stay together and reports remain reviewable.
- The final customization layer uses `maxLayers = 4` for runtime helpers, metadata, generated filesystem files, and the Nix database.
- Previously built semantic layers are passed explicitly. Their transitive `nestedLayers` metadata is cleared in the compiler so nix2container does not expand duplicate parent layers into oversized arguments.

CI checks reject layer plans that exceed the configured count budget. OCI artifact checks read the final nix2container image JSON and reject any `layers[].size` value above `budget.maxLayerSize`, so the limit is enforced against the actual registry blob sizes rather than the planning estimate.

## VS Code FHS Runtime

VS Code server components and common extension helpers expect several conventional Linux paths that are not normally present in a pure Nix image. The FHS runtime provides only the compatibility surface required for those tools:

- `/bin/bash`, `/bin/sh`, `/usr/bin/env`, and common archive/network tools point at Nix-provided binaries.
- The architecture dynamic loader path, for example `/lib64/ld-linux-x86-64.so.2`, points at `nix-ld`.
- `NIX_LD` points at the real glibc loader and `NIX_LD_LIBRARY_PATH` includes glibc plus the GCC runtime libraries.
- `/usr/lib/libc.so.6` and `/usr/lib/libstdc++.so.6` expose the glibc and GCC runtime libraries for tools that probe conventional library paths.
- CA bundle environment variables point at `/etc/ssl/certs/ca-certificates.crt`.

The FHS layer is compatibility glue for VS Code and extension tooling. It does not turn the image into a general FHS distribution.

## Native Libraries

Image modules keep command packages separate from native libraries:

- `devcontainer.packages` adds command-line tools and ordinary software to the image and `PATH`.
- `devcontainer.libraries.runtime` adds runtime `.so` outputs. These are included in `NIX_LD_LIBRARY_PATH` together with the dynamic runtime-library profile.
- `devcontainer.libraries.build` adds libraries needed for compiling and linking. The build set automatically contributes runtime outputs for test execution, and exposes headers, `pkg-config`, CMake prefixes, `CPATH`, `LIBRARY_PATH`, `NIX_CFLAGS_COMPILE`, and `NIX_LDFLAGS`.

Language modules can opt into preset-specific variables. Go enables `cgo` by default, Rust enables `rust-bindgen` by default, and callers can override inherited presets with normal Nix module priorities such as `lib.mkForce [ ]`.

Runtime library layers use bucket `70-runtime-libraries`; build-only outputs such as headers use `71-build-libraries`. Build layers link `/include` in addition to `/bin`, `/lib`, `/lib64`, `/share`, and `/etc`.

`LD_LIBRARY_PATH` is not exported by default because it changes dynamic-loader search precedence for all programs in the container. Images can opt in with `devcontainer.libraries.exportLdLibraryPath = true`, and individual devcontainers can still set `remoteEnv.LD_LIBRARY_PATH` for FFI, JNA, Python `ctypes`, non-Nix toolchains, or legacy build systems.

## Locale And Shell

Locale and shell runtime data are compiled separately from ordinary command packages. The `14-shell-runtime` layer holds `pkgs.glibcLocales` for `LOCALE_ARCHIVE` and `pkgs.bash-completion` for interactive Bash completion.

The default locale contract is `LANG=en_US.UTF-8`, `LANGUAGE=en_US:en`, `XDG_CONFIG_DIRS=/etc/xdg`, and `XDG_DATA_DIRS=/usr/local/share:/usr/share:/share`. `LC_ALL` is intentionally unset by default because it overrides every locale category; image modules should use `devcontainer.locale.lc` for targeted `LC_*` overrides. Library presets that need `XDG_DATA_DIRS`, such as GTK or Qt, prepend their dynamic build profile share directories and then append the base XDG data directories with duplicates removed.

Generated shell files are `/etc/profile`, `/etc/bashrc`, and `/etc/bash.bashrc`. Login shells load `/etc/profile`; interactive Bash shells load aliases, a lightweight prompt, history settings, bash completion, and `command_not_found_handle`. The command-not-found handler only queries the local nix-index database and returns 127. It does not run `comma`, install software, call the network, or execute project commands.

Image modules extend aliases through `devcontainer.shell.aliases`. Alias names are restricted to letters, numbers, `_`, `-`, `.`, and `+`, and values are shell-escaped when `/etc/bashrc` is rendered. Go images add the `gobuild-small` alias from the Go language module.

## Fonts And Fontconfig

All images include a shared font runtime in bucket `02-fonts-runtime`. The core
fonts module adds Noto Latin, CJK, symbol, and emoji coverage plus fontconfig
tools, while the font compiler generates `/etc/fonts/fonts.conf` and
devcontainer-specific default font aliases.

The fontconfig integration reuses `pkgs.makeFontsConf` and follows NixOS
`defaultFonts` and `aliases` semantics, but it does not import the NixOS
fontconfig module. This keeps the container compiler independent from NixOS
`environment.*` and AppArmor options.

See [Fonts And Fontconfig](fonts-fontconfig.md) for the detailed design,
generated files, report contract, cache policy, and maintenance checklist.

## Nix Database

Images enable nix2container's `initializeNixDatabase` support. The generated Nix database registers the store paths already present in the image, makes `/nix`, `/nix/store`, and `/nix/var/nix` writable by the container user, and avoids a separate registration workaround at startup.

This is required for `devpkg`, which installs ad-hoc user packages with `nix profile add`. Without the database, Nix can see paths on disk that are not registered in `/nix/var/nix/db`, causing profile installs to fail or to reference missing store paths.

The generated filesystem also includes `/etc/nixpkgs/config.nix` with the same
nixpkgs policy as the build. Container env sets `NIXPKGS_CONFIG`,
`NIXPKGS_ALLOW_UNFREE`, `NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM`, and
`NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE`. `devpkg` runs flake eval/install commands
with `--impure` so packages such as Google Chrome and Microsoft Edge can read
those defaults instead of failing the unfree license check.

The generated filesystem layer intentionally does not create `/nix` paths. `/nix` ownership and database contents are owned by the nix2container database layer to avoid tar path collisions.

## Runtime Contract

Images set:

- `User = "vscode"`
- `WorkingDir = "/workspaces"`
- `HOME=/home/vscode`
- entrypoint `/usr/local/bin/devcontainer-entrypoint`
- default command `sleep infinity`

Generated filesystem content includes `/etc/passwd`, `/etc/group`, `/etc/os-release`, `/home/vscode`, `/tmp`, `/var/tmp`, `/run/user/1000`, and `/workspaces`.

The runtime contract is intentionally single-user. The only supported user is `vscode` with uid/gid `1000`; image modules and metadata snippets cannot set another `remoteUser`, `containerUser`, or `updateRemoteUserUID = true`. Project `.devcontainer/devcontainer.json` files should leave those fields unset, and `devcontainer-image check` reports an error if they try to override them.

## Metadata

The image label `devcontainer.metadata` is a JSON array. It includes remote/container user settings, container and remote environment, lifecycle commands, and VS Code customizations.
