{
  self,
  pkgs,
  lib,
  system,
  inputs,
}:
let
  compiler = rec {
    runtimePackages = import ../runtime {
      inherit pkgs lib;
    };

    nix2container = inputs.nix2container.packages.${system}.nix2container;

    evalImage = import ./compiler/eval.nix {
      inherit
        self
        pkgs
        lib
        system
        inputs
        ;
    };

    compileGraph = import ./compiler/graph.nix {
      inherit lib;
    };

    compileEnv = import ./compiler/env.nix {
      inherit lib;
    };

    compileMetadata = import ./compiler/metadata.nix {
      inherit lib;
    };

    compileLifecycle = import ./compiler/lifecycle.nix {
      inherit lib;
    };

    compileVscodeExtensions = import ./compiler/vscode-extensions.nix {
      inherit
        lib
        pkgs
        system
        inputs
        ;
    };

    compileFhsRuntime = import ./compiler/fhs-runtime.nix {
      inherit lib pkgs system;
    };

    compileFilesystem = import ./compiler/filesystem.nix {
      inherit pkgs lib;
    };

    compileLayers = import ./compiler/layers.nix {
      inherit lib pkgs;
    };

    compileImage = import ./compiler/image.nix {
      inherit
        pkgs
        lib
        runtimePackages
        nix2container
        ;
    };

    compileReports = import ./compiler/reports.nix {
      inherit pkgs lib;
    };

    mkImage =
      {
        module ? null,
        modules ? [ ],
      }:
      let
        evaluated = evalImage { modules = modules ++ lib.optional (module != null) module; };
        graph = compileGraph { config = evaluated.config; };
        env = compileEnv { config = evaluated.config; };
        metadata = compileMetadata {
          config = evaluated.config;
          compiledEnv = env;
        };
        lifecycle = compileLifecycle {
          config = evaluated.config;
        };
        vscodeExtensions = compileVscodeExtensions {
          config = evaluated.config;
        };
        fhsRuntime = compileFhsRuntime {
          config = evaluated.config;
        };
        filesystem = compileFilesystem {
          config = evaluated.config;
          compiledFhsRuntime = fhsRuntime;
        };
        layers = compileLayers {
          config = evaluated.config;
          compiledGraph = graph;
        };
        image = compileImage {
          config = evaluated.config;
          compiledEnv = env;
          compiledMetadata = metadata;
          compiledLifecycle = lifecycle;
          compiledVscodeExtensions = vscodeExtensions;
          compiledFhsRuntime = fhsRuntime;
          compiledFilesystem = filesystem;
          compiledGraph = graph;
          compiledLayers = layers;
        };
        reports = compileReports {
          config = evaluated.config;
          compiledGraph = graph;
          compiledEnv = env;
          compiledMetadata = metadata;
          compiledLifecycle = lifecycle;
          compiledVscodeExtensions = vscodeExtensions;
          compiledFhsRuntime = fhsRuntime;
          compiledFilesystem = filesystem;
          compiledLayers = layers;
        };
      in
      {
        inherit (evaluated) config options;
        inherit
          graph
          env
          metadata
          layers
          fhsRuntime
          filesystem
          ;
        inherit lifecycle vscodeExtensions;
        inherit (image)
          rootfs
          oci
          copyToDockerDaemon
          ;
        inherit (reports)
          graph-json
          graph-normalized-json
          graph-duplicates-report-json
          metadata-label-json
          metadata-merged-preview-json
          metadata-schema-report-json
          image-plan-json
          layer-plan-json
          env-report-json
          closure-report-json
          extensions-report-json
          fhs-runtime-report-json
          filesystem-report-json
          security-report-json
          smoke-test-plan-json
          ci-plan-json
          tasks-json
          extensions-index-json
          reports
          smoke
          ;
      };
  };
in
compiler
