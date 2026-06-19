{ lib, ... }:
{
  imports = [ ./go.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "go-web";
    toolsets.dataNetwork.enable = true;
    languages.nodejs.enable = true;
  };
}
