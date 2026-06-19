{ pkgs, lib }:
{
  config,
  compiledGraph,
  compiledEnv,
  compiledMetadata,
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
      extensions = config.devcontainer.vscode.extensions;
      projection = config.devcontainer.vscode.preinstall.projection;
    };
  docker-access-report-json =
    jsonFile "docker-access-report.json" {
      enabled = config.devcontainer.dockerAccess.enable;
      defaultMode = config.devcontainer.dockerAccess.defaultMode;
      mounts = config.devcontainer.dockerAccess.mounts;
      containerEnv = config.devcontainer.dockerAccess.containerEnv;
      securityClass =
        if config.devcontainer.dockerAccess.enable then
          "docker-daemon-access"
        else
          "trusted";
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
        "layer-plan.json"
        "metadata-label.json"
        "env-report.json"
        "extensions-report.json"
        "docker-access-report.json"
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
    layer-plan-json
    env-report-json
    closure-report-json
    extensions-report-json
    docker-access-report-json
    smoke-test-plan-json
    ci-plan-json
    reports
    ;
  smoke = smoke-test-plan-json;
}
