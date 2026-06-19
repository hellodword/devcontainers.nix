{ lib, ... }:
{
  imports = [ ./rust.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "rust-web";
    toolsets.dataNetwork.enable = true;
    languages.nodejs.enable = true;
    tests.smoke = [
      {
        name = "rust-web-stack";
        command = [
          "bash"
          "-lc"
          "rustc --version && cargo --version && node --version && npm --version && pnpm --version"
        ];
      }
    ];
  };
}
