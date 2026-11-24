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
  cacheEnv = {
    GOPATH = "/home/vscode/.local/share/go";
    GOBIN = "/home/vscode/.local/share/go/bin";
    GOMODCACHE = "/home/vscode/.cache/go/pkg/mod";
    GOCACHE = "/home/vscode/.cache/go-build";
  };
  devEnv = {
    GOTELEMETRY = "off";
    GOTOOLCHAIN = "local";
  };
in
{
  inherit usrPackages cacheEnv devEnv;
  storeDeps = usrPackages;
  pathSegments = [ "/home/vscode/.local/share/go/bin" ];
  env = cacheEnv // devEnv;
}
