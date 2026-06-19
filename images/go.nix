{ lib, ... }:
{
  imports = [ ./nix.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 900 "go";
    runtimes.cEnv.enable = true;
    runtimes.python.enable = true;
    runtimes.nodejs.enable = true;
    languages.go.enable = true;
  };
}
