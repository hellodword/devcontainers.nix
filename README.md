# devcontainers.nix

`devcontainers.nix` builds x86_64-linux VS Code Dev Container OCI images with Nix and nix2container.

The published images provide Nix, common development tools, VS Code-compatible runtime glue, preconfigured editor metadata, and the `devpkg` helper for adding packages inside a container.

## Motivation

I heavily rely on `Dev Containers` and `gVisor` in VS Code to set up development environments and isolate different projects.

Initially, I used a base image and added a bunch of Dev Container features. However, this approach had a significant drawback: Dev Container features do not actually include real content. They are mostly shell scripts built locally during container creation, which made rebuilds slow and noisy.

To improve this, I adopted the official recommended approach of using the Dev Container CLI to build and publish Dev Container images to GHCR. That was much better, but it introduced two new problems. First, VS Code extensions and some SDKs still could not be included cleanly, which created a heavy mental burden during every rebuild unless I wrote endless shell scripts to handle them one by one. Second, once the images became complex, they were difficult to layer properly; trying to keep packages up to date with nightly image builds made image pulls unnecessarily expensive.

After two years of these setups, I decided to completely rework everything using Nix. To my surprise, I found it much simpler and better than I had imagined.

1. With `nixpkgs`, there is a massive collection of available packages, along with binary caches, multi-architecture support, and a batteries-included package toolchain.
2. Nix makes Docker images reproducible, which was practically unattainable with traditional `docker build`, or at least very hard to achieve.
3. The Nix store is hash-based, making it incredibly easy to avoid wasting space with duplicate files.
4. Tools like `pkgs.dockerTools` and `nix2container.buildImage` allow for flexible layering. I can manually organize which packages and files go into the same layer. More impressively, these layers are fully reproducible and shareable, effectively turning Docker pulls into true incremental updates.
5. Nix also makes real VS Code GUI E2E tests practical: this project can build NixOS VM tests that open the generated devcontainer in VS Code and verify X11/Wayland GUI forwarding, lifecycle tasks, terminal integration, and smoke probes.

The initial Nix implementation lives on the `v0` branch. This version was refactored from that `v0` base through vibe coding.

## Quick Start

Published images:

<!-- BEGIN GENERATED:image-refs -->

- `ghcr.io/hellodword/devcontainers-nix:latest`
- `ghcr.io/hellodword/devcontainers-go:latest`
- `ghcr.io/hellodword/devcontainers-go:1.26`
- `ghcr.io/hellodword/devcontainers-go:1.25`
- `ghcr.io/hellodword/devcontainers-go:web`
- `ghcr.io/hellodword/devcontainers-nodejs:latest`
- `ghcr.io/hellodword/devcontainers-nodejs:26`
- `ghcr.io/hellodword/devcontainers-nodejs:24`
- `ghcr.io/hellodword/devcontainers-python3:latest`
- `ghcr.io/hellodword/devcontainers-python3:3.13`
- `ghcr.io/hellodword/devcontainers-python3:web`
- `ghcr.io/hellodword/devcontainers-rust:latest`
- `ghcr.io/hellodword/devcontainers-rust:web`
- `ghcr.io/hellodword/devcontainers-flutter:latest`
<!-- END GENERATED:image-refs -->

Create `.devcontainer/devcontainer.json`:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-go:latest"
}
```

<details><summary>Working with agents:</summary>
```json
{
  "image": "ghcr.io/hellodword/devcontainers-go:web",
  "mounts": [
    "source=${localEnv:HOME}/dev/workspace/agents-misc/.agents,target=${containerWorkspaceFolder}/.agents,type=bind,readonly",
    "source=${localEnv:HOME}/dev/workspace/agents-misc/AGENTS.md,target=${containerWorkspaceFolder}/AGENTS.md,type=bind,readonly",
    "source=${localEnv:HOME}/dev/workspace/agents-misc/codex/config/codex_hook_forwarder.py,target=/etc/codex/codex_hook_forwarder.py,type=bind,readonly",
    {
      "source": "${localEnv:HOME}/.codex",
      "target": "/home/vscode/.codex",
      "type": "bind"
    }
  ],
  "containerEnv": {
    "AI_COMMIT_COAUTHOR": "Codex <noreply@openai.com>"
  }
}
```
</details>

Inside the container, add ad-hoc packages with `devpkg`:

```sh
devpkg add cowsay
cowsay hello
devpkg list
devpkg remove cowsay
```

Each generated image carries its source version inside the image:

```sh
cat /usr/share/devcontainer/version.json
printf '%s\n' "$DEVCONTAINERS_NIX_VERSION"
```

For a dirty flake source, the version value includes the `-dirty` suffix.

## Documentation

- [Documentation Index](docs/index.md)
- [Usage](docs/usage.md)
- [Architecture](docs/architecture.md)
- [Development and Maintenance](docs/development.md)
