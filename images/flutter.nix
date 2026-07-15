{ lib, ... }:
{
  imports = [ ./dev.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "flutter";
    profiles = {
      "language/nodejs".enable = lib.mkDefault true;
      "language/flutter".enable = lib.mkDefault true;
      "runtime/android-sdk".enable = lib.mkDefault true;
      "runtime/browser-gui-gpu".enable = lib.mkDefault true;
      "language/flutter-rust-bridge".enable = lib.mkDefault true;
    };
  };
}
