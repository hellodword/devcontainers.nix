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

  previousTargetPatterns = [
    "go-[0-9]+_[0-9]+"
    "nodejs-[0-9]+"
  ];

  disallowedTargetSuffixes = [ "-latest" ];
}
