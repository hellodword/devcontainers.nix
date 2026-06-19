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
