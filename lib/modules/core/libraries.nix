{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  moduleTypes = import ../types.nix { inherit lib; };
  inherit (moduleTypes) libraryPresetNames;
  libraryUtils = import ../../library-utils.nix { inherit lib; };
  cfg = config.devcontainer.libraries;

  runtimeOutputs = libraryUtils.uniqueDrvs (
    (map libraryUtils.runtimeOutput cfg.runtime) ++ (map libraryUtils.runtimeOutput cfg.build)
  );
  buildOutputs = libraryUtils.uniqueDrvs (lib.concatMap libraryUtils.buildOutputs cfg.build);
  buildLayerOutputs = libraryUtils.withoutDrvs runtimeOutputs buildOutputs;
in
{
  options.devcontainer.libraries = {
    runtime = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };
    build = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };
    exportLdLibraryPath = mkOption {
      type = types.bool;
      default = false;
    };
    ccWrapperFlags = mkOption {
      type = types.bool;
      default = true;
    };
    presets = mkOption {
      type = types.listOf (types.enum libraryPresetNames);
      default = [ ];
    };
    dynamicRuntimeProfile = mkOption {
      type = types.str;
      default = "$XDG_DATA_HOME/devpkg/runtime-libraries/profile";
    };
    dynamicBuildProfile = mkOption {
      type = types.str;
      default = "$XDG_DATA_HOME/devpkg/build-libraries/profile";
    };
  };

  config.devcontainer = lib.mkMerge [
    {
      layers.bucketDefinitions = {
        "runtime-libraries" = {
          order = 50000;
          owner = "core/libraries";
          purpose = "Runtime library closures shared across language profiles.";
        };
        "build-libraries" = {
          order = 50100;
          owner = "core/libraries";
          purpose = "Build-time library outputs shared across language profiles.";
        };
      };
    }

    (lib.mkIf (runtimeOutputs != [ ]) {
      graph.nodes."libraries/runtime" = {
        kind = "library-runtime";
        group = "runtime-libraries";
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
        group = "build-libraries";
        paths = buildLayerOutputs;
        stability = "stable";
        sharing = "cross-language";
        priority = 71;
        securityClass = "trusted";
      };
    })
  ];
}
