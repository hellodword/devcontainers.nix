{ lib, ... }:
{
  imports = [ ./nix.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 900 "nix-dind";
    dockerAccess.enable = true;
  };
}
