{ self, pkgs, lib, system }:
let
  compiler = rec {
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

    compileLayers = import ./compiler/layers.nix {
      inherit lib;
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
        layers = compileLayers {
          config = evaluated.config;
          compiledGraph = graph;
        };
        reports = compileReports {
          config = evaluated.config;
          compiledGraph = graph;
          compiledEnv = env;
          compiledMetadata = metadata;
          compiledLayers = layers;
        };
      in
      {
        inherit (evaluated) config options;
        inherit graph env metadata layers;
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
          reports
          smoke
          ;
      };
  };
in
compiler
