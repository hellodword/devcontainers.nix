{ lib, ... }:
{
  imports = [ ./nix.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 900 "python";
    profiles = {
      "runtime/c-env".enable = lib.mkDefault true;
      "runtime/python".enable = lib.mkDefault true;
      "runtime/nodejs".enable = lib.mkDefault true;
      "language/python".enable = lib.mkDefault true;
    };
  };
}
