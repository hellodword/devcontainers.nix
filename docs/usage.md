# Usage, Workspace Layout, and UID/GID Derivation

## Standard Workspace Layout

`:latest` embeds Dev Container metadata in its `devcontainer.metadata` image label:

- `remoteUser`: `vscode` (`1000:1000`)
- `containerUser`: `vscode`
- `updateRemoteUserUID`: `false`
- `init`: `true`
- `overrideCommand`: `true`
- `securityOpt`: `["label=disable"]`
- `userEnvProbe`: `"loginInteractiveShell"`
- Default mount: `source=${localWorkspaceFolder}/.devcontainer,target=/workspaces/${localWorkspaceFolderBasename}/.devcontainer,type=bind,readonly`

When opening a repository under the standard `/workspaces/<repo>` path on a host where the user has `uid = 1000` and `gid = 1000`, `.devcontainer/devcontainer.json` only needs the image reference:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest"
}
```

The default read-only `.devcontainer` bind mount prevents processes inside the container from modifying container launch configuration or lifecycle hooks inside the workspace.

## Custom `workspaceFolder` Layout

When a project overrides `workspaceFolder` and `workspaceMount` to mount the repository at a custom path (such as `/workspace`), add a matching read-only bind mount for `.devcontainer` at that target path:

```json
{
  "image": "ghcr.io/hellodword/devcontainers-dev:latest",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind",
  "workspaceFolder": "/workspace",
  "mounts": [
    "source=${localWorkspaceFolder}/.devcontainer,target=/workspace/.devcontainer,type=bind,readonly"
  ]
}
```

## Entrypoint Identity Boundary

Both `:latest` and `:agent` use `/usr/bin/devcontainer-entrypoint` with default command `["/bin/bash"]`:

- Interactive shell: `docker run --rm -it ghcr.io/hellodword/devcontainers-dev:latest`
- One-shot command passthrough: `docker run --rm ghcr.io/hellodword/devcontainers-dev:agent nix --version`
- Background daemon with clean `SIGTERM` handling via `tini -g`: `docker run -d ghcr.io/hellodword/devcontainers-dev:agent sleep infinity`

At startup, `devcontainer-entrypoint` verifies that the process effective `uid:gid` matches the `vscode` entry in `/etc/passwd`. Starting the container as `root` (`--user 0`) or with an unmapped runtime `--user <uid>:<gid>` fails immediately with exit code `126`. The entrypoint never performs runtime recursive `chown` traversal.

## Non-Default Host UID/GID Thin Derivation

When the host user does not use `1000:1000`, derive a thin local image at build time with `/usr/bin/devcontainer-set-user-id` using this 6-line `.devcontainer/Dockerfile`:

```dockerfile
FROM ghcr.io/hellodword/devcontainers-dev@sha256:<digest>
USER root
ARG DEV_UID=1000
ARG DEV_GID=1000
RUN /usr/bin/devcontainer-set-user-id --uid "$DEV_UID" --gid "$DEV_GID"
ENV XDG_RUNTIME_DIR=/run/user/${DEV_UID}
USER vscode
```

Pair it with `.devcontainer/devcontainer.json`:

```json
{
  "build": {
    "dockerfile": "Dockerfile",
    "args": {
      "DEV_UID": "1234",
      "DEV_GID": "1235"
    }
  }
}
```

`devcontainer-set-user-id` updates `/etc/passwd` and `/etc/group`, migrates ownership of `/home/vscode`, `/var/lib/devcontainer`, `/run/user/<uid>`, and `/nix/var/nix`, and leaves `/nix/store` package files untouched in lower layers so builds complete in seconds without layer duplication.

Automated tooling can compute a deterministic local tag key from the base manifest digest, target IDs, and helper protocol version (`devcontainer-set-user-id --version`, currently `devcontainer-set-user-id 1`):

```text
sha256("<base_manifest_digest>:<uid>:<gid>:<helper_version>")
```
