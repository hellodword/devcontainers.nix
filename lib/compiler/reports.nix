{ pkgs, lib }:
{
  config,
  compiledGraph,
  compiledEnv,
  compiledMetadata,
  compiledLifecycle,
  compiledVscodeExtensions,
  compiledDockerAccess,
  compiledFhsRuntime,
  compiledLayers,
}:
let
  jsonFile = name: value: pkgs.writeText name (builtins.toJSON value);

  graph-json = jsonFile "graph.json" { inherit (compiledGraph) nodes groups; };
  graph-normalized-json = jsonFile "graph-normalized.json" compiledGraph;
  graph-duplicates-report-json = jsonFile "graph-duplicates-report.json" compiledGraph.duplicates;
  metadata-label-json = jsonFile "metadata-label.json" compiledMetadata.label;
  metadata-merged-preview-json =
    jsonFile "metadata-merged-preview.json" compiledMetadata.mergedPreview;
  metadata-schema-report-json =
    jsonFile "metadata-schema-report.json" compiledMetadata.schemaReport;
  image-plan-json =
    jsonFile "image-plan.json" {
      image = config.devcontainer.image.name;
      packageCount = builtins.length config.devcontainer.packages;
      layerStrategy = compiledLayers.budget.strategy;
      entrypoint = [ "/usr/local/bin/devcontainer-entrypoint" ];
      smokeTestCount = builtins.length config.devcontainer.tests.smoke;
    };
  tasks-json =
    jsonFile "tasks.json" { tasks = compiledLifecycle.tasks; };
  extensions-index-json =
    jsonFile "extensions-index.json" {
      extensions = compiledVscodeExtensions.extensions;
      projectionTargets = compiledVscodeExtensions.projectionTargets;
    };
  layer-plan-json = jsonFile "layer-plan.json" compiledLayers;
  env-report-json = jsonFile "env-report.json" compiledEnv;
  closure-report-json =
    jsonFile "closure-report.json" {
      image = config.devcontainer.image.name;
      packageCount = builtins.length config.devcontainer.packages;
      packages = map (drv: drv.pname or drv.name or "<unknown>") config.devcontainer.packages;
    };
  extensions-report-json =
    jsonFile "extensions-report.json" {
      image = config.devcontainer.image.name;
      extensionCount = builtins.length config.devcontainer.vscode.extensions;
      extensions = compiledVscodeExtensions.extensions;
      projection = config.devcontainer.vscode.preinstall.projection;
      validation = {
        nativeExtensions =
          map (extension: extension.id)
            (builtins.filter (extension: extension.native) compiledVscodeExtensions.extensions);
        fhsRuntime = config.devcontainer.vscode.preinstall.validation.fhsRuntime;
        noNetworkDuringProjection = config.devcontainer.vscode.preinstall.validation.noNetworkDuringProjection;
        allArtifactsLocked =
          builtins.all
            (extension:
              extension ? sourceLock
              && extension.sourceLock ? sha256
              && extension.sourceLock ? manifestSha256
              && extension.sourceLock ? vsixSha256)
            compiledVscodeExtensions.extensions;
        companionToolsProvidedByNix = true;
      };
    };
  docker-access-report-json =
    jsonFile "docker-access-report.json" compiledDockerAccess;
  fhs-runtime-report-json =
    jsonFile "fhs-runtime-report.json" {
      enabled = compiledFhsRuntime.enabled;
      symlinkCount = builtins.length compiledFhsRuntime.symlinks;
      dynamicLoader =
        lib.findFirst
          (link: lib.hasInfix "ld-linux" link.target)
          null
          compiledFhsRuntime.symlinks;
    };
  security-report-json =
    jsonFile "security-report.json" {
      secretsBakedIntoImage = false;
      lifecycleLogRedaction = true;
      extensionProjectionLogRedaction = true;
      dockerAccessOnlyInNixDind =
        config.devcontainer.image.name == "nix-dind" || !compiledDockerAccess.enabled;
      remoteTcpRequiresTls = true;
      hostSocketMarkedHighPrivilege =
        !compiledDockerAccess.enabled || compiledDockerAccess.privilegeReport.level == "high";
      extensionArtifactsLocked =
        builtins.all (extension: extension ? sourceLock && extension.sourceLock ? sha256) compiledVscodeExtensions.extensions;
      dynamicPackageFreezeReviewable = true;
      uvxAutoRunFromShellInit = false;
      npxAutoRunFromShellInit = false;
      shellInitHasNoSideEffects = true;
    };
  smoke-test-plan-json =
    jsonFile "smoke-test-plan.json" {
      image = config.devcontainer.image.name;
      tests = config.devcontainer.tests.smoke;
    };
  ci-plan-json =
    jsonFile "ci-plan.json" {
      image = config.devcontainer.image.name;
      workflow = "build-image-${config.devcontainer.image.name}.yml";
      architectures = config.devcontainer.image.architectures;
      reportFiles = [
        "graph.json"
        "metadata-merged-preview.json"
        "metadata-schema-report.json"
        "image-plan.json"
        "layer-plan.json"
        "metadata-label.json"
        "env-report.json"
        "closure-report.json"
        "extensions-index.json"
        "extensions-report.json"
        "docker-access-report.json"
        "fhs-runtime-report.json"
        "security-report.json"
        "smoke-test-plan.json"
      ];
    };

  reports =
    pkgs.linkFarm "reports-${config.devcontainer.image.name}" [
      {
        name = "graph.json";
        path = graph-json;
      }
      {
        name = "graph-normalized.json";
        path = graph-normalized-json;
      }
      {
        name = "graph-duplicates-report.json";
        path = graph-duplicates-report-json;
      }
      {
        name = "metadata-label.json";
        path = metadata-label-json;
      }
      {
        name = "metadata-merged-preview.json";
        path = metadata-merged-preview-json;
      }
      {
        name = "metadata-schema-report.json";
        path = metadata-schema-report-json;
      }
      {
        name = "image-plan.json";
        path = image-plan-json;
      }
      {
        name = "tasks.json";
        path = tasks-json;
      }
      {
        name = "extensions-index.json";
        path = extensions-index-json;
      }
      {
        name = "layer-plan.json";
        path = layer-plan-json;
      }
      {
        name = "env-report.json";
        path = env-report-json;
      }
      {
        name = "closure-report.json";
        path = closure-report-json;
      }
      {
        name = "extensions-report.json";
        path = extensions-report-json;
      }
      {
        name = "docker-access-report.json";
        path = docker-access-report-json;
      }
      {
        name = "fhs-runtime-report.json";
        path = fhs-runtime-report-json;
      }
      {
        name = "security-report.json";
        path = security-report-json;
      }
      {
        name = "smoke-test-plan.json";
        path = smoke-test-plan-json;
      }
      {
        name = "ci-plan.json";
        path = ci-plan-json;
      }
    ];
in
{
  inherit
    graph-json
    graph-normalized-json
    graph-duplicates-report-json
    metadata-label-json
    metadata-merged-preview-json
    metadata-schema-report-json
    image-plan-json
    tasks-json
    extensions-index-json
    layer-plan-json
    env-report-json
    closure-report-json
    extensions-report-json
    docker-access-report-json
    fhs-runtime-report-json
    security-report-json
    smoke-test-plan-json
    ci-plan-json
    reports
    ;
  smoke = smoke-test-plan-json;
}
