# Go compiler, language server, debugger, linters, and GOPATH/GOCACHE environment.
{ pkgs }:
let
  goPkg = pkgs.go_latest or pkgs.go;
  usrPackages = [
    goPkg
    pkgs.gopls
    pkgs.delve
    pkgs.golangci-lint
    pkgs.gotools
    pkgs.govulncheck
    pkgs.gotests
    pkgs.gomodifytags
    pkgs.impl
    pkgs.protoc-gen-go
  ];
in
{
  inherit usrPackages;
  storeDeps = usrPackages;
  pathSegments = [ "/home/vscode/.local/share/go/bin" ];
  env = {
    GOTELEMETRY = "off";
    GOTOOLCHAIN = "local";
    GOPATH = "/home/vscode/.local/share/go";
    GOBIN = "/home/vscode/.local/share/go/bin";
    GOMODCACHE = "/home/vscode/.cache/go/pkg/mod";
    GOCACHE = "/home/vscode/.cache/go-build";
  };
}
