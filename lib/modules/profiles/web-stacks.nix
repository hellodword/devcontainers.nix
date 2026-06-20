{ ... }:
{
  config.devcontainer.profiles = {
    "image/python-web" = {
      kind = "image";
      group = "99-fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
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

    "image/go-web" = {
      kind = "image";
      group = "99-fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
      tests.smoke = [
        {
          name = "go-web-stack";
          command = [
            "bash"
            "-lc"
            "go version && gopls version && node --version && npm --version && pnpm --version"
          ];
        }
      ];
    };

    "image/rust-web" = {
      kind = "image";
      group = "99-fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
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
  };
}
