{ ... }:
{
  config.devcontainer.profiles = {
    "image/python3-web" = {
      kind = "image";
      group = "fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
      tests.cases."web.python" = {
        tags = [
          "smoke"
          "web"
          "python"
        ];
        command = [
          "bash"
          "-lc"
          "python --version && uv --version && node --version && npm --version && pnpm --version && ruff --version && eslint --version && prettier --version"
        ];
      };
    };

    "image/go-web" = {
      kind = "image";
      group = "fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
      tests.cases."web.go" = {
        tags = [
          "smoke"
          "web"
          "go"
        ];
        command = [
          "bash"
          "-lc"
          "go version && gopls version && node --version && npm --version && pnpm --version"
        ];
      };
    };

    "image/rust-web" = {
      kind = "image";
      group = "fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
      tests.cases."web.rust" = {
        tags = [
          "smoke"
          "web"
          "rust"
        ];
        command = [
          "bash"
          "-lc"
          "rustc --version && cargo --version && node --version && npm --version && pnpm --version"
        ];
      };
    };
  };
}
