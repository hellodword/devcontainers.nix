{ lib, config, ... }:
let
  libraryUtils = import ../../library-utils.nix { inherit lib; };
  cfg = config.devcontainer.libraries;

  runtimeOutputs = libraryUtils.uniqueDrvs (
    (map libraryUtils.runtimeOutput cfg.runtime) ++ (map libraryUtils.runtimeOutput cfg.build)
  );
  buildOutputs = libraryUtils.uniqueDrvs (lib.concatMap libraryUtils.buildOutputs cfg.build);
  buildLayerOutputs = libraryUtils.withoutDrvs runtimeOutputs buildOutputs;
in
{
  config.devcontainer = lib.mkMerge [
    (lib.mkIf (runtimeOutputs != [ ]) {
      graph.nodes."libraries/runtime" = {
        kind = "library-runtime";
        group = "70-runtime-libraries";
        paths = runtimeOutputs;
        stability = "stable";
        sharing = "cross-language";
        priority = 72;
        securityClass = "trusted";
      };
    })
    (lib.mkIf (buildLayerOutputs != [ ]) {
      graph.nodes."libraries/build" = {
        kind = "library-build";
        group = "71-build-libraries";
        paths = buildLayerOutputs;
        stability = "stable";
        sharing = "cross-language";
        priority = 71;
        securityClass = "trusted";
      };
    })
  ];
}
