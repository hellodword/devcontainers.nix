{ lib, ... }:
{
  imports = [ ./nix.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 900 "rust";
    runtimes.cEnv.enable = true;
    runtimes.python.enable = true;
    runtimes.nodejs.enable = true;
    languages.rust.enable = true;
  };
}
