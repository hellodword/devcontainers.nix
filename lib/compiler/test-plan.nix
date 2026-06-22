{ lib }:
{
  config,
  compiledProfiles,
}:
let
  catalog = import ../tests/smoke-catalog.nix { inherit lib config; };
  topLevelCapabilities = config.devcontainer.tests.capabilities;
  profileCapabilities = lib.concatMap (profile: profile.tests.capabilities) compiledProfiles.enabled;
  declaredCapabilities = topLevelCapabilities ++ profileCapabilities;
  capabilities = lib.unique declaredCapabilities;
  unknownCapabilities = builtins.filter (id: !(builtins.hasAttr id catalog)) capabilities;
  tests = map (id: catalog.${id}) capabilities;
in
if unknownCapabilities != [ ] then
  builtins.throw "unknown devcontainer smoke capabilities: ${lib.concatStringsSep ", " unknownCapabilities}"
else
  {
    inherit
      declaredCapabilities
      capabilities
      tests
      ;
    report = {
      declaredCapabilities = declaredCapabilities;
      resolvedCapabilities = capabilities;
      testCount = builtins.length tests;
    };
  }
