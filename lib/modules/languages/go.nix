{
  lib,
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
  config = lib.mkIf cfg.enable {
    environment.systemPackages = packages;
    devcontainer.libraries.presets = lib.mkBefore [ "cgo" ];
    devcontainer.vscode.extensions = [ "golang.go" ];
    devcontainer.vscode.settings = {
      "go.toolsManagement.checkForUpdates" = "off";
      "go.toolsManagement.autoUpdate" = false;
      "go.gopath" = "/home/vscode/.local/share/go";
      "go.goroot" = "/usr/share/go";
    };
    environment.variables = {
      GOTELEMETRY = "off";
      GOTOOLCHAIN = "local";
      GOPATH = "$XDG_DATA_HOME/go";
      GOBIN = "$XDG_DATA_HOME/go/bin";
      GOMODCACHE = "$XDG_CACHE_HOME/go/pkg/mod";
      GOCACHE = "$XDG_CACHE_HOME/go-build";
    };
    environment.variableOrigins = {
      GOTELEMETRY = [ "languages.go" ];
      GOTOOLCHAIN = [ "languages.go" ];
      GOPATH = [ "languages.go" ];
      GOBIN = [ "languages.go" ];
      GOMODCACHE = [ "languages.go" ];
      GOCACHE = [ "languages.go" ];
    };
    devcontainer.path.segments.language = [ "$GOBIN" ];
    devcontainer.path.segmentOrigins.language = {
      "$GOBIN" = [ "languages.go" ];
    };
    environment.shellAliases.gobuild-small = ''go build -trimpath -ldflags "-s -w -buildid="'';
    environment.shellAliases.go-build = ''go build -trimpath -ldflags "-s -w -buildid="'';
    environment.shellAliasOrigins.gobuild-small = [ "languages.go" ];
    environment.shellAliasOrigins.go-build = [ "languages.go" ];
    devcontainer.graph.nodes."language/go" = {
      kind = "language";
      group = "50-go-language";
      paths = packages;
      stability = "medium";
      sharing = "image-family";
      priority = 70;
      securityClass = "trusted";
    };
    devcontainer.tests.smoke = [
      {
        name = "go-version";
        command = [
          "go"
          "version"
        ];
      }
      {
        name = "gopls-version";
        command = [
          "gopls"
          "version"
        ];
      }
      {
        name = "go-tooling";
        command = [
          "bash"
          "-lc"
          "dlv version && golangci-lint version && (govulncheck -version || govulncheck --version) && command -v gotests gomodifytags impl protoc-gen-go >/dev/null"
        ];
      }
      {
        name = "go-runtime-deps";
        command = [
          "bash"
          "-lc"
          "python --version && node --version && cc --version"
        ];
      }
    ];
  };
}
