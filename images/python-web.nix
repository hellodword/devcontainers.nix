{ lib, ... }:
{
  imports = [ ./python.nix ];

  config.devcontainer = {
    image.name = lib.mkOverride 800 "python-web";
    toolsets.dataNetwork.enable = true;
    languages.nodejs.enable = true;
    tests.smoke = [
      {
        name = "python-web-stack";
        command = [
          "bash"
          "-lc"
          "python --version && uv --version && node --version && npm --version && pnpm --version"
        ];
      }
      {
        name = "python-web-formatters";
        command = [
          "bash"
          "-lc"
          "ruff --version && eslint --version && prettier --version"
        ];
      }
    ];
  };
}
