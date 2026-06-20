{ lib, ... }:
{
  imports = [ ./rust.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "rust-web";
    profiles = {
      "toolset/data-network".enable = lib.mkDefault true;
      "language/nodejs".enable = lib.mkDefault true;
      "image/rust-web".enable = lib.mkDefault true;
    };
  };
}
