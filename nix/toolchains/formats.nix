# Multi-format language servers, formatters, linters, Protobuf tooling, and Wayland diagnostics.
{ pkgs }:
let
  usrPackages = with pkgs; [
    just-lsp
    prettier
    shellcheck
    shfmt
    editorconfig-core-c
    taplo
    yaml-language-server
    lemminx
    minijinja
    protobuf
    protols
    buf
    protolint
    grpcurl
    api-linter
    wayland-utils
  ];
in
{
  inherit usrPackages;
  storeDeps = usrPackages;
  pathSegments = [ ];
  env = { };
}
