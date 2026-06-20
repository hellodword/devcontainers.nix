{ lib, ... }:
{
  imports = [ ./python.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "python-web";
    profiles = {
      "toolset/data-network".enable = lib.mkDefault true;
      "language/nodejs".enable = lib.mkDefault true;
      "image/python-web".enable = lib.mkDefault true;
    };
  };
}
