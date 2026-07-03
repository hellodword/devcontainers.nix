{ lib, ... }:
{
  imports = [ ./python.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "python3-web";
    profiles = {
      "toolset/data-network".enable = lib.mkDefault true;
      "language/nodejs".enable = lib.mkDefault true;
      "image/python3-web" = {
        enable = lib.mkDefault true;
        kind = "image";
        group = "fallback";
        packages = [ ];
        priority = 10;
        stability = "medium";
        sharing = "single-image";
        securityClass = "trusted";
        tests.cases."web.python" = {
          tags = [
            "smoke"
            "web"
            "python"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                python --version
                uv --version
                node --version
                npm --version
                pnpm --version
                ruff --version
                eslint --version
                prettier --version
              '';
            }
          ];
        };
      };
    };
  };
}
