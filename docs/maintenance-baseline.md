# Maintenance Registry Baseline

This note records the pre-migration maintenance surface for the registry
consolidation work. It is intentionally descriptive: no image behavior, package
selection, report content, workflow policy, or E2E behavior changes here.

## Drift Scope

- `flake/docs.nix` owns `docsMetadata` separately from the image target list.
- `flake/targets.nix` owns `imageTargetList`, while image modules under
  `images/` own part of `devcontainer.image`.
- `lib/compiler/reports.nix` separately lists report derivations, link farm
  entries, and `ci-plan.json` `reportFiles`.
- `tests/ci/check-reports.py` keeps its own required report file lists.
- Runtime helper knowledge is spread across `runtime/default.nix`, `flake.nix`,
  `lib/compiler/image.nix`, and `flake/checks/tooling.nix`.
- `tests/e2e/vscode-gui.nix` owns session names, while
  `docs/e2e-testing.md` hand-writes the session table.
- `tests/fixtures/*.nix` files are not referenced by default checks, smoke
  tests, or E2E tests.

## Baseline Commands

Run from repository root:

```sh
git status --short
nix eval --no-eval-cache --json .#lib.x86_64-linux.imageNames
nix eval --no-eval-cache --json .#images --apply 'images: builtins.mapAttrs (_: image: { inherit (image.config.devcontainer.image) family tags name; }) images'
nix eval --no-eval-cache --json .#e2e.x86_64-linux --apply builtins.attrNames
nix flake check --no-build
```

`git status --short` was empty before the baseline note was added.

`nix flake check --no-build` passed. The only warnings were the accepted custom
flake outputs:

- `unknown flake output 'images'`
- `unknown flake output 'e2e'`

## Image Names

```json
["nix","go","go-1_25","go-web","nodejs","nodejs-24","python3","python3-web","rust","rust-web","flutter"]
```

## Image Metadata

```json
{
  "flutter": {
    "family": "flutter",
    "name": "flutter",
    "tags": [
      "latest"
    ]
  },
  "go": {
    "family": "go",
    "name": "go",
    "tags": [
      "latest",
      "1.26"
    ]
  },
  "go-1_25": {
    "family": "go",
    "name": "go-1_25",
    "tags": [
      "1.25"
    ]
  },
  "go-web": {
    "family": "go",
    "name": "go-web",
    "tags": [
      "web"
    ]
  },
  "nix": {
    "family": "nix",
    "name": "nix",
    "tags": [
      "latest"
    ]
  },
  "nodejs": {
    "family": "nodejs",
    "name": "nodejs",
    "tags": [
      "latest",
      "26"
    ]
  },
  "nodejs-24": {
    "family": "nodejs",
    "name": "nodejs-24",
    "tags": [
      "24"
    ]
  },
  "python3": {
    "family": "python3",
    "name": "python3",
    "tags": [
      "latest",
      "3.13"
    ]
  },
  "python3-web": {
    "family": "python3",
    "name": "python3-web",
    "tags": [
      "web"
    ]
  },
  "rust": {
    "family": "rust",
    "name": "rust",
    "tags": [
      "latest"
    ]
  },
  "rust-web": {
    "family": "rust",
    "name": "rust-web",
    "tags": [
      "web"
    ]
  }
}
```

## E2E Outputs

```json
["e2e-vscode-flutter-wayland-kde","e2e-vscode-flutter-wayland-sway","e2e-vscode-flutter-x11-i3","e2e-vscode-flutter-x11-xfce","e2e-vscode-go-1_25-wayland-kde","e2e-vscode-go-1_25-wayland-sway","e2e-vscode-go-1_25-x11-i3","e2e-vscode-go-1_25-x11-xfce","e2e-vscode-go-wayland-kde","e2e-vscode-go-wayland-sway","e2e-vscode-go-web-wayland-kde","e2e-vscode-go-web-wayland-sway","e2e-vscode-go-web-x11-i3","e2e-vscode-go-web-x11-xfce","e2e-vscode-go-x11-i3","e2e-vscode-go-x11-xfce","e2e-vscode-nix-wayland-kde","e2e-vscode-nix-wayland-sway","e2e-vscode-nix-x11-i3","e2e-vscode-nix-x11-xfce","e2e-vscode-nodejs-24-wayland-kde","e2e-vscode-nodejs-24-wayland-sway","e2e-vscode-nodejs-24-x11-i3","e2e-vscode-nodejs-24-x11-xfce","e2e-vscode-nodejs-wayland-kde","e2e-vscode-nodejs-wayland-sway","e2e-vscode-nodejs-x11-i3","e2e-vscode-nodejs-x11-xfce","e2e-vscode-python3-wayland-kde","e2e-vscode-python3-wayland-sway","e2e-vscode-python3-web-wayland-kde","e2e-vscode-python3-web-wayland-sway","e2e-vscode-python3-web-x11-i3","e2e-vscode-python3-web-x11-xfce","e2e-vscode-python3-x11-i3","e2e-vscode-python3-x11-xfce","e2e-vscode-rust-wayland-kde","e2e-vscode-rust-wayland-sway","e2e-vscode-rust-web-wayland-kde","e2e-vscode-rust-web-wayland-sway","e2e-vscode-rust-web-x11-i3","e2e-vscode-rust-web-x11-xfce","e2e-vscode-rust-x11-i3","e2e-vscode-rust-x11-xfce"]
```
