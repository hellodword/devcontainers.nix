{
  requiredTargets = [
    "nix"
    "go"
    "go-web"
    "nodejs"
    "python3"
    "python3-web"
    "rust"
    "rust-web"
    "flutter"
  ];

  # Keep empty while no previous-version image targets are published.
  previousTargetPatterns = [ ];

  disallowedTargetSuffixes = [ "-latest" ];
}
