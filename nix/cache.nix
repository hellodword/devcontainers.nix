# Signed OCI cache configuration and redistribution policy for devcontainers.nix.
{
  core,
  lib,
}:
let
  identity = builtins.fromJSON (builtins.readFile ./cache-identity.json);

  upstreamCoreCache = {
    registry = "ghcr.io";
    repository = "hellodword/nixos-config";
    publicKey = "nixos-config-1:NfExPInFgDi/deX689T1M10hEORDGSZYRUapJMRbWM8=";
  };

  config = core.lib.cache.mkCacheConfig {
    target = identity;
    extraRepositories = [ upstreamCoreCache ];
    listenAddress = "172.17.0.1";
    ciListenAddress = "127.0.0.2";
    port = 37515;
    optionalInclude = "/home/vscode/.local/state/devcontainer/nix-local-cache.conf";
  };

  mkPolicy =
    {
      flakeOutPath,
      candidates ? [ ],
      extraRestricted ? [ ],
      extraExcluded ? [ ],
      bundles ? [ ],
      extraPrivateBuilds ? [ ],
    }:
    core.lib.cache.mkPolicy {
      inherit
        lib
        flakeOutPath
        candidates
        extraRestricted
        extraExcluded
        bundles
        extraPrivateBuilds
        ;
    };
in
{
  inherit
    identity
    upstreamCoreCache
    config
    mkPolicy
    ;
  inherit (config) public local ci;
}
