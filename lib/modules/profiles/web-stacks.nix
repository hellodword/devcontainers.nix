{ ... }:
{
  config.devcontainer.profiles = {
    "image/python3-web" = {
      kind = "image";
      group = "99-fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
      tests.capabilities = [ "web.python" ];
    };

    "image/go-web" = {
      kind = "image";
      group = "99-fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
      tests.capabilities = [ "web.go" ];
    };

    "image/rust-web" = {
      kind = "image";
      group = "99-fallback";
      packages = [ ];
      priority = 10;
      stability = "medium";
      sharing = "single-image";
      securityClass = "trusted";
      tests.capabilities = [ "web.rust" ];
    };
  };
}
