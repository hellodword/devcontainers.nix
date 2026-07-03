{ lib, ... }:
{
  imports = [ ./rust.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "rust-web";
    profiles = {
      "toolset/data-network".enable = lib.mkDefault true;
      "language/nodejs".enable = lib.mkDefault true;
      "image/rust-web" = {
        enable = lib.mkDefault true;
        kind = "image";
        group = "fallback";
        packages = [ ];
        priority = 10;
        stability = "medium";
        sharing = "single-image";
        securityClass = "trusted";
        tests.cases."web.rust" = {
          tags = [
            "smoke"
            "web"
            "rust"
          ];
          scripts = [
            {
              shell = "bash";
              interactive = false;
              command = ''
                set -e
                rustc --version
                cargo --version
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
