{ lib, ... }:
{
  imports = [ ./go.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "go-web";
    profiles = {
      "toolset/data-network".enable = lib.mkDefault true;
      "language/nodejs".enable = lib.mkDefault true;
      "image/go-web" = {
        enable = lib.mkDefault true;
        kind = "image";
        group = "fallback";
        packages = [ ];
        priority = 10;
        stability = "medium";
        sharing = "single-image";
        securityClass = "trusted";
        tests.cases."web.go" = {
          tags = [
            "smoke"
            "web"
            "go"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                go version
                gopls version
                node --version
                npm --version
                pnpm --version
              '';
            }
          ];
        };
      };
    };
  };
}
