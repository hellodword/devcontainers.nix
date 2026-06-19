{ lib, ... }:
{
  imports = [ ./nix.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 900 "python";
    runtimes.cEnv.enable = true;
    runtimes.nodejs.enable = true;
    languages.python.enable = true;
  };
}
