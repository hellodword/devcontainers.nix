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
  compiledFlakeInputs,
  compiledLibraries,
  compiledMetadata,
  compiledLifecycle,
  compiledShell,
  compiledFonts,
  compiledProfiles ? {
    report = { };
    testCaseIds = [ ];
    extensionIds = [ ];
    settings = { };
  },
  compiledTests ? {
    report = { };
    tests = [ ];
    caseIds = [ ];
    declaredCaseIds = [ ];
  },
  compiledVscodeExtensions,
  compiledFhsRuntime,
  compiledFilesystem,
  compiledLayers,
  compiledSecurity ? {
    report = { };
  },
}:
let
  jsonFile = name: value: pkgs.writeText name (builtins.toJSON value);
  displayPathString = path: builtins.unsafeDiscardStringContext (toString path);
  pathsForMembers =
    members: lib.unique (lib.concatMap (name: compiledGraph.rawNodes.${name}.paths) members);

  graph-json = jsonFile "graph.json" { inherit (compiledGraph) nodes groups; };
  graph-normalized-json = jsonFile "graph-normalized.json" (removeAttrs compiledGraph [ "rawNodes" ]);
  graph-duplicates-report-json = jsonFile "graph-duplicates-report.json" compiledGraph.duplicates;
  metadata-label-json = jsonFile "metadata-label.json" compiledMetadata.label;
  metadata-merged-preview-json = jsonFile "metadata-merged-preview.json" compiledMetadata.mergedPreview;
  metadata-schema-report-json = jsonFile "metadata-schema-report.json" compiledMetadata.schemaReport;
  flake-inputs-json = pkgs.writeText "flake-inputs.json" compiledFlakeInputs.json;
  sourceVersion = config.devcontainer.image.sourceVersion;
  version-json = jsonFile "version.json" sourceVersion;
  allSmokeTests = compiledTests.tests;
  imagePlan = {
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
    smokeTestCount = builtins.length allSmokeTests;
    inherit sourceVersion;
  };
  smokePlan = {
    image = config.devcontainer.image.name;
    tests = allSmokeTests;
    caseIds = compiledTests.caseIds;
  };
  reportData = {
    inherit imagePlan smokePlan;
    security = compiledSecurity.report;
  };
  profile-report-json = jsonFile "profile-report.json" (
    compiledProfiles.report
    // {
      tests = (compiledProfiles.report.tests or { }) // {
        declaredCases = compiledTests.declaredCaseIds;
        resolvedCases = compiledTests.caseIds;
      };
    }
  );
  image-plan-json = jsonFile "image-plan.json" imagePlan;
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
    extensions = compiledVscodeExtensions.projectionExtensions;
    projectionTargets = compiledVscodeExtensions.projectionTargets;
  };
  layer-plan-json = jsonFile "layer-plan.json" compiledLayers;
  layerClosureInputs = map (
    layer:
    let
      rootPaths = pathsForMembers layer.members;
      closureInfo = pkgs.closureInfo { inherit rootPaths; };
    in
    {
      inherit closureInfo;
      data = {
        inherit (layer)
          group
          members
          priority
          pathCount
          storePaths
          packages
          ;
        rootPathCount = builtins.length rootPaths;
        rootPaths = map displayPathString rootPaths;
        closureInfoPath = "${closureInfo}";
      };
    }
  ) compiledLayers.layers;
  layer-closure-report-input-json = jsonFile "layer-closure-report-input.json" {
    image = config.devcontainer.image.name;
    family = config.devcontainer.image.family;
    tag = imageTag;
    budget = compiledLayers.budget;
    order = compiledLayers.order;
    layerCount = builtins.length compiledLayers.layers;
    layers = map (entry: entry.data) layerClosureInputs;
  };
  layerClosureDeps = lib.concatMapStringsSep "\n" (
    entry: "test -f ${entry.closureInfo}/total-nar-size"
  ) layerClosureInputs;
  layer-closure-report-json =
    pkgs.runCommand "layer-closure-report.json"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        preferLocalBuild = true;
      }
      ''
        ${layerClosureDeps}
        python3 - ${layer-closure-report-input-json} "$out" <<'PY'
        import json
        import pathlib
        import sys

        source = pathlib.Path(sys.argv[1])
        output = pathlib.Path(sys.argv[2])
        data = json.loads(source.read_text(encoding="utf-8"))

        for layer in data["layers"]:
            closure_path = pathlib.Path(layer.pop("closureInfoPath"))
            total_nar_size = (closure_path / "total-nar-size").read_text(encoding="utf-8").strip()
            store_paths = [
                line
                for line in (closure_path / "store-paths").read_text(encoding="utf-8").splitlines()
                if line
            ]
            layer["closureSizeBytes"] = int(total_nar_size or "0")
            layer["closurePathCount"] = len(store_paths)
            layer["closureStorePaths"] = store_paths

        output.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        PY
      '';
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
    extensionCount = builtins.length compiledVscodeExtensions.extensions;
    extensions = compiledVscodeExtensions.extensions;
    artifacts = compiledVscodeExtensions.artifacts;
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
        && extension.sourceLock ? ref
        && extension.sourceLock ? sha256
        && extension.sourceLock ? archiveName
      ) compiledVscodeExtensions.extensions;
      companionToolsProvidedByNix =
        (compiledProfiles.report.validation or { }).companionToolsProvidedByNix or false;
      missingCompanionTools = (compiledProfiles.report.validation or { }).missingCompanionTools or [ ];
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
    vscodeMachineSettings = compiledFilesystem.vscodeMachineSettings;
    symlinks = compiledFilesystem.symlinks;
    shellFiles = compiledFilesystem.shellFiles;
    commandNotFoundHook = {
      enabled = config.programs.bash.enable && config.programs.bash.commandNotFound.enable;
      path = "/etc/bashrc";
      database = "nix-index-database";
    };
  };
  security-report-json = jsonFile "security-report.json" compiledSecurity.report;
  smoke-test-plan-json = jsonFile "smoke-test-plan.json" smokePlan;
  baseReportEntries = [
    {
      name = "graph.json";
      path = graph-json;
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
      name = "profile-report.json";
      path = profile-report-json;
    }
    {
      name = "image-plan.json";
      path = image-plan-json;
    }
    {
      name = "version.json";
      path = version-json;
    }
    {
      name = "flake-inputs.json";
      path = flake-inputs-json;
    }
    {
      name = "layer-plan.json";
      path = layer-plan-json;
    }
    {
      name = "layer-closure-report.json";
      path = layer-closure-report-json;
    }
    {
      name = "metadata-label.json";
      path = metadata-label-json;
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
      name = "extensions-index.json";
      path = extensions-index-json;
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
      name = "graph-normalized.json";
      path = graph-normalized-json;
      includeInCiPlan = false;
    }
    {
      name = "graph-duplicates-report.json";
      path = graph-duplicates-report-json;
      includeInCiPlan = false;
    }
    {
      name = "tasks.json";
      path = tasks-json;
      includeInCiPlan = false;
    }
  ];
  ciReportFileNames = map (entry: entry.name) (
    builtins.filter (entry: entry.includeInCiPlan or true) baseReportEntries
  );
  ci-plan-json = jsonFile "ci-plan.json" {
    image = config.devcontainer.image.name;
    family = config.devcontainer.image.family;
    tag = imageTag;
    imageRef = imageRef;
    publishRefs = publishRefs;
    architectures = config.devcontainer.image.architectures;
    inherit sourceVersion;
    reportFiles = ciReportFileNames;
  };
  reportEntries = baseReportEntries ++ [
    {
      name = "ci-plan.json";
      path = ci-plan-json;
      includeInCiPlan = false;
    }
  ];
  reports = pkgs.linkFarm "reports-${config.devcontainer.image.name}" (
    map (entry: { inherit (entry) name path; }) reportEntries
  );
in
{
  inherit
    graph-json
    graph-normalized-json
    graph-duplicates-report-json
    metadata-label-json
    metadata-merged-preview-json
    metadata-schema-report-json
    profile-report-json
    flake-inputs-json
    version-json
    image-plan-json
    tasks-json
    extensions-index-json
    layer-plan-json
    layer-closure-report-json
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
    reportData
    ;
  smoke = smoke-test-plan-json;
}
