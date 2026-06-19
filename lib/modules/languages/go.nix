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
  ];
in
{
  config = lib.mkIf cfg.enable {
    devcontainer.packages = packages;
    devcontainer.vscode.extensions = [ "golang.go" ];
    devcontainer.vscode.settings = {
      "go.toolsManagement.checkForUpdates" = "off";
      "go.toolsManagement.autoUpdate" = false;
      "go.gopath" = "/home/vscode/.local/share/go";
      "go.goroot" = "/usr/local/go";
    };
    devcontainer.env.container = {
      GOTELEMETRY = "off";
      GOTOOLCHAIN = "local";
      GOPATH = "$XDG_DATA_HOME/go";
      GOBIN = "$XDG_DATA_HOME/go/bin";
      GOMODCACHE = "$XDG_CACHE_HOME/go/pkg/mod";
      GOCACHE = "$XDG_CACHE_HOME/go-build";
    };
    devcontainer.env.origins.container = {
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
          "dlv version && golangci-lint version && govulncheck -version || govulncheck --version"
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
