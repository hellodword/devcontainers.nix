{ lib, ... }:
{
  imports = [ ./python.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "python-web";
    toolsets.dataNetwork.enable = true;
    languages.nodejs.enable = true;
  };
}
