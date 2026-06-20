{ pkgs, lib }:
{
  config,
  compiledEnvironment ? {
    systemPackages = [ ];
    packageNames = [ ];
    report = { };
  },
  compiledGraph,
  compiledEnv,
  compiledLibraries,
  compiledMetadata,
  compiledLifecycle,
  compiledShell,
  compiledFonts,
  compiledVscodeExtensions,
  compiledFhsRuntime,
  compiledFilesystem,
  compiledLayers,
}:
let
  jsonFile = name: value: pkgs.writeText name (builtins.toJSON value);

  graph-json = jsonFile "graph.json" { inherit (compiledGraph) nodes groups; };
  graph-normalized-json = jsonFile "graph-normalized.json" compiledGraph;
  graph-duplicates-report-json = jsonFile "graph-duplicates-report.json" compiledGraph.duplicates;
  metadata-label-json = jsonFile "metadata-label.json" compiledMetadata.label;
  metadata-merged-preview-json = jsonFile "metadata-merged-preview.json" compiledMetadata.mergedPreview;
  metadata-schema-report-json = jsonFile "metadata-schema-report.json" compiledMetadata.schemaReport;
  image-plan-json = jsonFile "image-plan.json" {
    image = config.devcontainer.image.name;
    family = config.devcontainer.image.family;
    tag = imageTag;
    imageRef = imageRef;
    publishRefs = publishRefs;
    backend = "nix2container";
    packageCount = builtins.length compiledEnvironment.systemPackages;
    runtimeLibraryCount = builtins.length compiledLibraries.runtime.storePaths;
    buildLibraryCount = builtins.length compiledLibraries.build.storePaths;
    layerStrategy = compiledLayers.budget.strategy;
    user = config.devcontainer.user.containerUser;
    workingDir = "/workspaces";
    entrypoint = [ "/usr/bin/devcontainer-entrypoint" ];
    smokeTestCount = builtins.length config.devcontainer.tests.smoke;
  };
  imageTag =
    if config.devcontainer.image.tags == [ ] then
      "latest"
    else
      builtins.head config.devcontainer.image.tags;
  imageRef = "ghcr.io/hellodword/devcontainers-${config.devcontainer.image.family}:${imageTag}";
  publishRefs = map (
    tag: "ghcr.io/hellodword/devcontainers-${config.devcontainer.image.family}:${tag}"
  ) config.devcontainer.image.tags;
  tasks-json = jsonFile "tasks.json" { tasks = compiledLifecycle.tasks; };
  extensions-index-json = jsonFile "extensions-index.json" {
    extensions = compiledVscodeExtensions.extensions;
    projectionTargets = compiledVscodeExtensions.projectionTargets;
  };
  layer-plan-json = jsonFile "layer-plan.json" compiledLayers;
  env-report-json = jsonFile "env-report.json" (
    compiledEnv
    // {
      environment = compiledEnvironment.report;
    }
  );
  libraries-report-json = jsonFile "libraries-report.json" compiledLibraries.report;
  closure-report-json = jsonFile "closure-report.json" {
    image = config.devcontainer.image.name;
    packageCount = builtins.length compiledEnvironment.systemPackages;
    packages = compiledEnvironment.packageNames;
    runtimeLibraries = compiledLibraries.runtime.storePaths;
    buildLibraries = compiledLibraries.build.storePaths;
  };
  extensions-report-json = jsonFile "extensions-report.json" {
    image = config.devcontainer.image.name;
    extensionCount = builtins.length config.devcontainer.vscode.extensions;
    extensions = compiledVscodeExtensions.extensions;
    projection = config.devcontainer.vscode.preinstall.projection;
    validation = {
      nativeExtensions = map (extension: extension.id) (
        builtins.filter (extension: extension.native) compiledVscodeExtensions.extensions
      );
      fhsRuntime = config.devcontainer.vscode.preinstall.validation.fhsRuntime;
      noNetworkDuringProjection =
        config.devcontainer.vscode.preinstall.validation.noNetworkDuringProjection;
      allArtifactsLocked = builtins.all (
        extension:
        extension ? sourceLock
        && extension.sourceLock ? sha256
        && extension.sourceLock ? manifestSha256
        && extension.sourceLock ? vsixSha256
      ) compiledVscodeExtensions.extensions;
      companionToolsProvidedByNix = true;
    };
  };
  fhs-runtime-report-json = jsonFile "fhs-runtime-report.json" {
    enabled = compiledFhsRuntime.enabled;
    dynamicLoaderMode = compiledFhsRuntime.dynamicLoaderMode;
    realGlibcLoader = compiledFhsRuntime.realGlibcLoader;
    nixLdEnv = compiledFhsRuntime.nixLdEnv;
    caCertificates = compiledFhsRuntime.caCertificates;
    symlinkCount = builtins.length compiledFhsRuntime.symlinks;
    symlinks = compiledFhsRuntime.symlinks;
    dynamicLoader = lib.findFirst (
      link: lib.hasInfix "ld-linux" link.target
    ) null compiledFhsRuntime.symlinks;
  };
  shell-report-json = jsonFile "shell-report.json" compiledShell.report;
  fontconfig-report-json = jsonFile "fontconfig-report.json" compiledFonts.report;
  filesystem-report-json = jsonFile "filesystem-report.json" {
    user = {
      inherit (config.devcontainer.user)
        name
        uid
        group
        gid
        home
        shell
        remoteUser
        containerUser
        ;
    };
    directories = compiledFilesystem.directories;
    passwd = compiledFilesystem.passwd;
    group = compiledFilesystem.group;
    osRelease = compiledFilesystem.osRelease;
    nixpkgsConfig = compiledFilesystem.nixpkgsConfig;
    etcFiles = compiledFilesystem.etcFiles;
    symlinks = compiledFilesystem.symlinks;
    shellFiles = compiledFilesystem.shellFiles;
    commandNotFoundHook = {
      enabled = config.programs.bash.enable && config.programs.bash.commandNotFound.enable;
      path = "/etc/bashrc";
      database = "nix-index-database";
    };
  };
  security-report-json = jsonFile "security-report.json" {
    secretsBakedIntoImage = false;
    lifecycleLogRedaction = true;
    extensionProjectionLogRedaction = true;
    dockerDaemonBakedIntoImage = false;
    dockerSocketMountedByDefault = false;
    dockerHostConfiguredByDefault = compiledEnv.containerEnv ? DOCKER_HOST;
    extensionArtifactsLocked = builtins.all (
      extension: extension ? sourceLock && extension.sourceLock ? sha256
    ) compiledVscodeExtensions.extensions;
    uvxAutoRunFromShellInit = false;
    npxAutoRunFromShellInit = false;
    shellInitHasNoSideEffects = true;
  };
  smoke-test-plan-json = jsonFile "smoke-test-plan.json" {
    image = config.devcontainer.image.name;
    tests = config.devcontainer.tests.smoke;
  };
  ci-plan-json = jsonFile "ci-plan.json" {
    image = config.devcontainer.image.name;
    family = config.devcontainer.image.family;
    tag = imageTag;
    imageRef = imageRef;
    publishRefs = publishRefs;
    architectures = config.devcontainer.image.architectures;
    reportFiles = [
      "graph.json"
      "metadata-merged-preview.json"
      "metadata-schema-report.json"
      "image-plan.json"
      "layer-plan.json"
      "metadata-label.json"
      "env-report.json"
      "libraries-report.json"
      "closure-report.json"
      "extensions-index.json"
      "extensions-report.json"
      "fhs-runtime-report.json"
      "fontconfig-report.json"
      "shell-report.json"
      "filesystem-report.json"
      "security-report.json"
      "smoke-test-plan.json"
    ];
  };

  reports = pkgs.linkFarm "reports-${config.devcontainer.image.name}" [
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
      name = "libraries-report.json";
      path = libraries-report-json;
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
      name = "fhs-runtime-report.json";
      path = fhs-runtime-report-json;
    }
    {
      name = "fontconfig-report.json";
      path = fontconfig-report-json;
    }
    {
      name = "shell-report.json";
      path = shell-report-json;
    }
    {
      name = "filesystem-report.json";
      path = filesystem-report-json;
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
    reports
    ;
  smoke = smoke-test-plan-json;
}
