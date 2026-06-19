{ lib, ... }:
{
  imports = [ ./nix.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 900 "nodejs";
    runtimes.cEnv.enable = true;
    runtimes.python.enable = true;
    languages.nodejs.enable = true;
  };
}
