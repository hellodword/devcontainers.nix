{
  requiredTargets = [
    "dev"
    "flutter"
  ];

  # Keep empty while no previous-version image targets are published.
  previousTargetPatterns = [ ];

  disallowedTargetSuffixes = [ "-latest" ];
}
