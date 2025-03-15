# devcontainers.nix

## Motivation

I heavily rely on `Dev Containers` and `gVisor` in VSCode to set up my development environments and isolate different projects.

Initially, I used a base image and added a bunch of Dev Container features. However, this approach had a significant drawback: Dev Container features don't actually include real content — they're just shell scripts that are built locally, which is quite slow.

To improve this, I adopted the official recommended approach of using the Dev Container CLI to build and publish Dev Container images to ghcr. While this solution was much better, it introduced two new issues: (1) VSCode extensions and some SDKs couldn't be included, leading to a heavy mental burden during every rebuild — unless I wrote endless shell scripts to handle them one by one; (2) such a complex image was difficult to layer properly, and attempting to keep the software packages up to date by publishing nightly builds resulted in significant costs during image pulls.

After two years of these setups, I decided to completely rework everything using Nix. To my surprise, I found it much simpler and better than I had imagined.

1. With `nixpkgs`, there’s a massive collection of available packages, along with binary caches, multi-arch support, and a battery-included package tool.
2. Nix makes Docker images reproducible, which was practically unattainable with traditional `docker build` (or at least very hard to achieve).
3. The Nix store is hash-based, making it incredibly easy to avoid wasting space with duplicate files.
4. Tools like `pkgs.dockerTools` and `nix2container.buildImage` allow for flexible layering. I can manually organize which packages and files go into the same layer. More impressively, these layers are fully reproducible and shareable, effectively turning Docker pulls into true incremental updates.

## TODO

- [x] environment variables
- [x] executable packages
- [x] vscode extensions from nixpkgs
- [x] vscode extensions from `nix-community/nix-vscode-extensions`
- [x] github actions dynamic matrix
- [x] github actions cache
  - [ ] audit
- [x] layered image
- [x] multiple arch
- [x] manually organized layers (nix2container)
- [x] devcontainers metadata
- [x] features
- [ ] bashrc
- [ ] FHS
- [ ] customization
- [ ] multiple tags
- [ ] flakeModule
- [ ] types

## Ref

- https://github.com/niksi-aalto/niksi-devcontainer
- https://github.com/nixos/nixpkgs/blob/nixos-unstable/doc/build-helpers/images/dockertools.section.md
- https://github.com/divnix/std/blob/5b19a01095518d1acbd1975b1903b83ace4fe0dd/src/lib/ops/mkDevOCI.nix#L23
  - https://github.com/divnix/std/blob/5b19a01095518d1acbd1975b1903b83ace4fe0dd/src/lib/ops/mkDevOCI.nix#L130
  - https://github.com/search?q=%2F%28%3F-i%29%5B%5E%5C%2F%5DmkDevOCI%2F+language%3Anix&type=code
- https://blog.eigenvalue.net/2023-nix2container-everything-once/
- https://github.com/wi2trier/gpu-server/blob/e9b9c3723e6ed8ff8c7c332393b223a80095332d/overlays/image-base.nix
- https://github.com/shikanime/shikanime/blob/ac87ec6cb43fe59c7b47eeb9b44dcfe66d2a8388/modules/nixos/hosts/devcontainer.nix
- https://github.com/KoviRobi/robs-cs/blob/0f529711a8102abbd8b0d4eda222ccafc0bd1496/devenv.nix#L107
- https://github.com/kolloch/n2c-mod
- https://github.com/cachix/devenv/tree/main/src/modules/languages
