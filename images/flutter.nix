{ lib, ... }:
{
  imports = [ ./rust.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "flutter";
    languages.nodejs.enable = true;
    languages.flutter.enable = true;
  };
}
