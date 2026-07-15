{ lib, ... }:
{
  config.devcontainer = {
    image = {
      name = lib.mkOverride 1000 "dev";
      tags = lib.mkDefault [ "latest" ];
    };

    profiles = {
      "runtime/base".enable = lib.mkDefault true;
      "runtime/c-env".enable = lib.mkDefault true;
      "runtime/nix".enable = lib.mkDefault true;
      "runtime/python".enable = lib.mkDefault true;
      "runtime/nodejs".enable = lib.mkDefault true;

      "toolset/foundation".enable = lib.mkDefault true;
      "toolset/source-control".enable = lib.mkDefault true;
      "toolset/fetch-archive".enable = lib.mkDefault true;
      "toolset/search-navigation".enable = lib.mkDefault true;
      "toolset/inspect-debug".enable = lib.mkDefault true;
      "toolset/workflow-format".enable = lib.mkDefault true;
      "toolset/editor-support".enable = lib.mkDefault true;
      "toolset/docker-client".enable = lib.mkDefault true;
      "toolset/data-network".enable = lib.mkDefault true;
      "toolset/nix-index".enable = lib.mkDefault true;
      "toolset/agents".enable = lib.mkDefault true;

      "editor/base".enable = lib.mkDefault true;

      "language/nix".enable = lib.mkDefault true;
      "language/nodejs".enable = lib.mkDefault true;
      "language/go".enable = lib.mkDefault true;
      "language/python".enable = lib.mkDefault true;
      "language/rust".enable = lib.mkDefault true;

      "image/dev" = {
        enable = lib.mkDefault true;
        kind = "image";
        group = "fallback";
        packages = [ ];
        priority = 10;
        stability = "medium";
        sharing = "single-image";
        securityClass = "trusted";
        tests.cases."image.dev" = {
          tags = [
            "smoke"
            "dev"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                nix --version
                node --version
                npm --version
                pnpm --version
                python --version
                uv --version
                ruff --version
                go version
                gopls version
                rustc --version
                cargo --version
                rust-analyzer --version
                http --version
              '';
            }
          ];
        };
      };
    };
  };
}
