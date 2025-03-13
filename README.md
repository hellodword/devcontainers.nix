# devcontainers.nix

## TODO

- [x] environment variables
- [x] executable packages
- [x] vscode extensions from nixpkgs
- [x] vscode extensions from `nix-community/nix-vscode-extensions`
- [x] github actions dynamic matrix
- [x] github actions cache
  - [ ] audit
- [x] layered image
- [ ] shell.nix to container
  - [ ] layer
- [x] multiple arch

## Ref

- https://github.com/niksi-aalto/niksi-devcontainer
- https://github.com/nixos/nixpkgs/blob/nixos-unstable/doc/build-helpers/images/dockertools.section.md
- https://github.com/divnix/std/blob/5b19a01095518d1acbd1975b1903b83ace4fe0dd/src/lib/ops/mkDevOCI.nix#L23
  - https://github.com/divnix/std/blob/5b19a01095518d1acbd1975b1903b83ace4fe0dd/src/lib/ops/mkDevOCI.nix#L130
  - https://github.com/search?q=%2F%28%3F-i%29%5B%5E%5C%2F%5DmkDevOCI%2F+language%3Anix&type=code
- https://blog.eigenvalue.net/2023-nix2container-everything-once/
- https://github.com/wi2trier/gpu-server/blob/e9b9c3723e6ed8ff8c7c332393b223a80095332d/overlays/image-base.nix
- https://github.com/shikanime/shikanime/blob/ac87ec6cb43fe59c7b47eeb9b44dcfe66d2a8388/modules/nixos/hosts/devcontainer.nix
