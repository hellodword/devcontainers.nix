{ lib, ... }:
{
  imports = [ ./go.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "go-web";
    toolsets.dataNetwork.enable = true;
    languages.nodejs.enable = true;
    tests.smoke = [
      {
        name = "go-web-stack";
        command = [ "bash" "-lc" "go version && gopls version && node --version && npm --version && pnpm --version" ];
      }
    ];
  };
}
