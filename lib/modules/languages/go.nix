{
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.languages.go;
  go = if cfg.package == null then pkgs.go else cfg.package;
  packages = [
    go
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
  config.devcontainer.profiles."language/go" = {
    kind = "language";
    group = "50-go-language";
    packages = packages;
    priority = 70;
    stability = "medium";
    sharing = "image-family";
    securityClass = "trusted";
    provides.commands = [
      "go"
      "gopls"
      "dlv"
      "golangci-lint"
      "govulncheck"
      "gotests"
      "gomodifytags"
      "impl"
      "protoc-gen-go"
    ];
    libraries.presets = [ "cgo" ];
    vscode = {
      extensions."golang.go" = {
        native = true;
        bucket = "84-vscode-extensions-go";
        companionTools = [
          "go"
          "gopls"
          "dlv"
        ];
      };
      settings = {
        "go.toolsManagement.checkForUpdates" = "off";
        "go.toolsManagement.autoUpdate" = false;
        "go.gopath" = "/home/vscode/.local/share/go";
        "go.goroot" = "/usr/share/go";
      };
    };
    env = {
      variables = {
        GOTELEMETRY = "off";
        GOTOOLCHAIN = "local";
        GOPATH = "$XDG_DATA_HOME/go";
        GOBIN = "$XDG_DATA_HOME/go/bin";
        GOMODCACHE = "$XDG_CACHE_HOME/go/pkg/mod";
        GOCACHE = "$XDG_CACHE_HOME/go-build";
      };
      path = [ "$GOBIN" ];
      aliases = {
        gobuild-small = ''go build -trimpath -ldflags "-s -w -buildid="'';
        go-build = ''go build -trimpath -ldflags "-s -w -buildid="'';
      };
    };
    tests.capabilities = [ "language.go" ];
  };
}
