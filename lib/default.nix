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
    runtimeHelpers = runtimePackages.__helpers;
    runtimeHelperList = runtimePackages.__helperList;

    nix2container = pkgs.nix2container;

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

    compileEnvironment = import ./compiler/environment.nix {
      inherit lib;
    };

    compileProfiles = import ./compiler/profiles.nix {
      inherit lib;
    };

    compileTestPlan = import ./compiler/test-plan.nix {
      inherit lib;
    };

    compileLibraries = import ./compiler/libraries.nix {
      inherit lib;
    };

    compileMetadata = import ./compiler/metadata.nix {
      inherit lib;
    };

    compileLifecycle = import ./compiler/lifecycle.nix {
      inherit lib;
    };

    compileShell = import ./compiler/shell.nix {
      inherit pkgs lib;
    };

    compileFonts = import ./compiler/fonts.nix {
      inherit pkgs lib;
    };

    compileVscodeExtensions = import ./compiler/vscode-extensions.nix {
      inherit lib pkgs;
    };

    compileFhsRuntime = import ./compiler/fhs-runtime.nix {
      inherit lib pkgs system;
    };

    compileFlakeInputs = import ./compiler/flake-inputs.nix {
      inherit inputs;
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
        runtimeHelpers
        runtimeHelperList
        nix2container
        ;
      lockedNixpkgsSource = inputs.nixpkgs.outPath;
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
        profiles = compileProfiles {
          config = evaluated.config;
        };
        environment = compileEnvironment {
          config = evaluated.config;
          compiledProfiles = profiles;
        };
        libraries = compileLibraries {
          config = evaluated.config;
          compiledEnvironment = environment;
          compiledProfiles = profiles;
        };
        graph = compileGraph {
          config = evaluated.config;
          compiledProfiles = profiles;
        };
        fhsRuntime = compileFhsRuntime {
          config = evaluated.config;
          compiledLibraries = libraries;
        };
        env = compileEnv {
          config = evaluated.config;
          compiledEnvironment = environment;
          compiledFhsRuntime = fhsRuntime;
          compiledLibraries = libraries;
          compiledProfiles = profiles;
        };
        lifecycle = compileLifecycle {
          config = evaluated.config;
          compiledProfiles = profiles;
        };
        shell = compileShell {
          config = evaluated.config;
          compiledEnvironment = environment;
          compiledEnv = env;
        };
        fonts = compileFonts {
          config = evaluated.config;
        };
        vscodeExtensions = compileVscodeExtensions {
          config = evaluated.config;
          compiledProfiles = profiles;
        };
        tests = compileTestPlan {
          config = evaluated.config;
          compiledProfiles = profiles;
        };
        metadata = compileMetadata {
          config = evaluated.config;
          compiledEnv = env;
          compiledProfiles = profiles;
        };
        filesystem = compileFilesystem {
          config = evaluated.config;
          compiledEnvironment = environment;
          compiledFhsRuntime = fhsRuntime;
          compiledShell = shell;
          compiledFonts = fonts;
          compiledProfiles = profiles;
        };
        layers = compileLayers {
          config = evaluated.config;
          compiledEnvironment = environment;
          compiledGraph = graph;
        };
        flakeInputs = compileFlakeInputs;
        reports = compileReports {
          config = evaluated.config;
          compiledEnvironment = environment;
          compiledGraph = graph;
          compiledEnv = env;
          compiledFlakeInputs = flakeInputs;
          compiledLibraries = libraries;
          compiledMetadata = metadata;
          compiledLifecycle = lifecycle;
          compiledShell = shell;
          compiledFonts = fonts;
          compiledProfiles = profiles;
          compiledTests = tests;
          compiledVscodeExtensions = vscodeExtensions;
          compiledFhsRuntime = fhsRuntime;
          compiledFilesystem = filesystem;
          compiledLayers = layers;
        };
        image = compileImage {
          config = evaluated.config;
          compiledEnvironment = environment;
          compiledEnv = env;
          compiledFlakeInputs = flakeInputs;
          compiledLibraries = libraries;
          compiledMetadata = metadata;
          compiledLifecycle = lifecycle;
          compiledShell = shell;
          compiledFonts = fonts;
          compiledVscodeExtensions = vscodeExtensions;
          compiledFhsRuntime = fhsRuntime;
          compiledFilesystem = filesystem;
          compiledGraph = graph;
          compiledLayers = layers;
          compiledReports = reports;
        };
      in
      {
        inherit (evaluated) config options;
        inherit
          graph
          environment
          profiles
          tests
          env
          libraries
          metadata
          layers
          fhsRuntime
          filesystem
          shell
          fonts
          flakeInputs
          ;
        inherit lifecycle vscodeExtensions;
        profileReport = profiles.report;
        inherit (image)
          rawOci
          rootfs
          oci
          validatedOci
          budgetCheck
          copyToDockerDaemon
          ;
        inherit (reports)
          graph-json
          graph-normalized-json
          graph-duplicates-report-json
          metadata-label-json
          metadata-merged-preview-json
          metadata-schema-report-json
          profile-report-json
          flake-inputs-json
          image-plan-json
          layer-plan-json
          env-report-json
          libraries-report-json
          closure-report-json
          extensions-report-json
          fhs-runtime-report-json
          fontconfig-report-json
          shell-report-json
          filesystem-report-json
          security-report-json
          smoke-test-plan-json
          ci-plan-json
          tasks-json
          extensions-index-json
          reports
          reportData
          smoke
          ;
      };
  };
in
compiler
