{ self, pkgs, lib, system }:
let
  compiler = rec {
    runtimePackages = import ../runtime {
      inherit pkgs lib;
    };

    evalImage = import ./compiler/eval.nix {
      inherit self pkgs lib system;
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
      inherit lib;
    };

    compileLayers = import ./compiler/layers.nix {
      inherit lib;
    };

    compileImage = import ./compiler/image.nix {
      inherit pkgs lib runtimePackages;
    };

    compileReports = import ./compiler/reports.nix {
      inherit pkgs lib;
    };

    mkImage =
      { module }:
      let
        evaluated = evalImage { modules = [ module ]; };
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
        };
        reports = compileReports {
          config = evaluated.config;
          compiledGraph = graph;
          compiledEnv = env;
          compiledMetadata = metadata;
          compiledLifecycle = lifecycle;
          compiledVscodeExtensions = vscodeExtensions;
          compiledLayers = layers;
        };
      in
      {
        inherit (evaluated) config options;
        inherit graph env metadata layers;
        inherit lifecycle vscodeExtensions;
        inherit (image) rootfs oci;
        inherit (reports)
          graph-json
          graph-normalized-json
          graph-duplicates-report-json
          metadata-label-json
          metadata-merged-preview-json
          metadata-schema-report-json
          layer-plan-json
          env-report-json
          closure-report-json
          extensions-report-json
          docker-access-report-json
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
