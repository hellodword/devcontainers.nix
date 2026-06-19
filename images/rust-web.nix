{ lib, ... }:
{
  imports = [ ./rust.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "rust-web";
    toolsets.dataNetwork.enable = true;
    languages.nodejs.enable = true;
  };
}
