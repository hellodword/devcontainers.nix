{ lib, ... }:
{
  imports = [ ./go.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "go-web";
    profiles = {
      "toolset/data-network".enable = lib.mkDefault true;
      "language/nodejs".enable = lib.mkDefault true;
      "image/go-web".enable = lib.mkDefault true;
    };
  };
}
