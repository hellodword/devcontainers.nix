{
  lib,
  runtimeHelpers ? { },
}:
{
  config,
  compiledEnvironment ? {
    packageNames = [ ];
    shellInit = "";
    interactiveShellInit = "";
    etc = [ ];
  },
  compiledEnv ? {
    containerEnv = { };
    remoteEnv = { };
    shellEnv = { };
  },
  compiledMetadata ? {
    mergedPreview = { };
  },
  compiledLifecycle ? {
    tasks = [ ];
  },
  compiledVscodeExtensions ? {
    extensions = [ ];
  },
  compiledLayers ? {
    layers = [ ];
  },
}:
let
  pathToString = path: lib.concatStringsSep "." path;
  lastPathPart = path: if path == [ ] then "" else lib.last path;
  mkFinding = source: path: {
    inherit source;
    path = pathToString path;
    field = lastPathPart path;
    count = 1;
  };

  compactLower =
    value:
    builtins.replaceStrings
      [
        " "
        "\t"
        "\""
        "'"
      ]
      [
        ""
        ""
        ""
        ""
      ]
      (lib.toLower value);
  hasSensitiveMarker =
    value:
    let
      text = compactLower value;
    in
    lib.any (marker: lib.hasInfix marker text) [
      "token="
      "token:"
      "password="
      "password:"
      "secret="
      "secret:"
      "apikey="
      "apikey:"
      "api-key="
      "api-key:"
      "accesskey="
      "accesskey:"
      "access-key="
      "access-key:"
      "privatekey="
      "privatekey:"
      "private-key="
      "private-key:"
    ];

  commandRegex = command: ".*(^|[;&|[:space:]])${command}([[:space:]]|$).*";
  commandWithArgsRegex =
    command: args: ".*(^|[;&|[:space:]])${command}[[:space:]]+${args}([[:space:]]|$).*";
  hasCommand = command: value: builtins.match (commandRegex command) (lib.toLower value) != null;
  hasCommandWithArgs =
    command: args: value:
    builtins.match (commandWithArgsRegex command args) (lib.toLower value) != null;

  walkStrings =
    predicate: source: path: value:
    if builtins.isString value then
      lib.optional (predicate value) (mkFinding source path)
    else if builtins.isList value then
      lib.concatLists (
        lib.imap0 (index: item: walkStrings predicate source (path ++ [ (toString index) ]) item) value
      )
    else if builtins.isAttrs value && !lib.isDerivation value then
      lib.concatLists (
        map (name: walkStrings predicate source (path ++ [ name ]) (builtins.getAttr name value)) (
          lib.sort lib.lessThan (builtins.attrNames value)
        )
      )
    else
      [ ];

  etcTextEntries = map (entry: {
    inherit (entry) name path text;
  }) (builtins.filter (entry: entry.text != null) (compiledEnvironment.etc or [ ]));

  secretFindings = lib.concatLists [
    (walkStrings hasSensitiveMarker "containerEnv" [ "containerEnv" ] compiledEnv.containerEnv)
    (walkStrings hasSensitiveMarker "remoteEnv" [ "remoteEnv" ] compiledEnv.remoteEnv)
    (walkStrings hasSensitiveMarker "shellEnv" [ "shellEnv" ] (compiledEnv.shellEnv or { }))
    (walkStrings hasSensitiveMarker "metadata" [ "metadata" ] compiledMetadata.mergedPreview)
    (walkStrings hasSensitiveMarker "shellInit" [ "shellInit" ] {
      shellInit = compiledEnvironment.shellInit or "";
      interactiveShellInit = compiledEnvironment.interactiveShellInit or "";
    })
    (walkStrings hasSensitiveMarker "lifecycleTasks" [ "lifecycleTasks" ] compiledLifecycle.tasks)
    (walkStrings hasSensitiveMarker "etcText" [ "etcText" ] etcTextEntries)
  ];

  dockerAccessKey = "docker" + "Access";
  hasDockerSocket =
    value:
    lib.any (marker: lib.hasInfix marker value) [
      "/var/run/docker.sock"
      "/run/docker.sock"
      "docker.sock"
    ];
  dockerSocketFindings =
    walkStrings hasDockerSocket "metadata" [ "metadata" ] compiledMetadata.mergedPreview
    ++ lib.optional (builtins.hasAttr dockerAccessKey compiledMetadata.mergedPreview) (
      mkFinding "metadata" [
        "metadata"
        dockerAccessKey
      ]
    );

  daemonMarkers = [
    "dockerd"
    "dockerd-rootless"
    "docker-containerd"
    "docker.service"
    "docker.socket"
    "moby"
  ];
  hasDaemonMarker =
    value:
    let
      text = lib.toLower value;
    in
    lib.any (marker: lib.hasInfix marker text) daemonMarkers;
  dockerDaemonFindings = lib.concatLists [
    (walkStrings hasDaemonMarker "packages" [ "packages" ] (compiledEnvironment.packageNames or [ ]))
    (walkStrings hasDaemonMarker "layers" [ "layers" ] (compiledLayers.layers or [ ]))
  ];

  requiredExtensionLockKeys = [
    "ref"
    "sha256"
    "archiveName"
  ];
  extensionLockFindings = lib.concatMap (
    extension:
    let
      extensionId = extension.id or "<unknown>";
      sourceLock = extension.sourceLock or { };
      missingKeys = builtins.filter (
        key:
        let
          value = sourceLock.${key} or null;
        in
        value == null || value == ""
      ) requiredExtensionLockKeys;
    in
    map (
      key:
      mkFinding "vscodeExtensions" [
        "extensions"
        extensionId
        "sourceLock"
        key
      ]
    ) missingKeys
  ) compiledVscodeExtensions.extensions;

  helperRedactionFindings =
    helperName: capability:
    let
      helper = runtimeHelpers.${helperName} or { };
      capabilities = helper.securityCapabilities or { };
      declared = capabilities.${capability} or false;
      checked = helper ? checkName && helper ? checkScript && helper ? checkEnvName;
    in
    lib.optional (!(declared && checked)) (
      mkFinding "runtimeHelpers" [
        "runtimeHelpers"
        helperName
        "securityCapabilities"
        capability
      ]
    );
  lifecycleRedactionFindings = helperRedactionFindings "devcontainer-task-runner" "redactsLifecycleLogs";
  projectionRedactionFindings = helperRedactionFindings "vscode-extension-projector" "redactsProjectionLogs";

  sideEffectPredicates = [
    {
      name = "npx";
      predicate = hasCommand "npx";
    }
    {
      name = "uvx";
      predicate = hasCommand "uvx";
    }
    {
      name = "curl";
      predicate = hasCommand "curl";
    }
    {
      name = "wget";
      predicate = hasCommand "wget";
    }
    {
      name = "git-clone";
      predicate = hasCommandWithArgs "git" "clone";
    }
    {
      name = "npm-install";
      predicate = hasCommandWithArgs "npm" "(install|i|exec)";
    }
    {
      name = "pip-install";
      predicate = hasCommandWithArgs "pip" "install";
    }
    {
      name = "nix-profile";
      predicate = hasCommandWithArgs "nix" "profile";
    }
    {
      name = "nix-env";
      predicate = hasCommand "nix-env";
    }
    {
      name = "file-mutation";
      predicate =
        value:
        lib.any (command: hasCommand command value) [
          "rm"
          "mv"
          "cp"
          "mkdir"
          "touch"
          "tee"
          "chmod"
          "chown"
        ];
    }
  ];
  shellInitValues = {
    shellInit = compiledEnvironment.shellInit or "";
    interactiveShellInit = compiledEnvironment.interactiveShellInit or "";
  };
  shellSideEffectFindings = lib.concatMap (
    rule: walkStrings rule.predicate "shellInit" [ "shellInit" ] shellInitValues
  ) sideEffectPredicates;
  npxFindings = walkStrings (hasCommand "npx") "shellInit" [ "shellInit" ] shellInitValues;
  uvxFindings = walkStrings (hasCommand "uvx") "shellInit" [ "shellInit" ] shellInitValues;

  mkCheck = summary: findings: evidence: {
    status = if findings == [ ] then "pass" else "fail";
    inherit summary;
    evidence = evidence // {
      findingCount = builtins.length findings;
      findings = findings;
    };
  };

  checks = {
    secretScan = mkCheck "No secret-like values are present in compiled image inputs." secretFindings {
      scannedSources = [
        "containerEnv"
        "remoteEnv"
        "shellEnv"
        "metadata"
        "shellInit"
        "lifecycleTasks"
        "etcText"
      ];
    };
    dockerSocket =
      mkCheck "Dev Container metadata does not expose a Docker socket by default." dockerSocketFindings
        {
          scannedSources = [ "metadata" ];
        };
    dockerDaemon =
      mkCheck "Compiled package and layer metadata do not declare Docker daemon components."
        dockerDaemonFindings
        {
          scannedSources = [
            "packages"
            "layers"
          ];
          markers = daemonMarkers;
        };
    extensionArtifacts =
      mkCheck "VS Code extensions include complete source lock metadata." extensionLockFindings
        {
          requiredKeys = requiredExtensionLockKeys;
          extensionCount = builtins.length compiledVscodeExtensions.extensions;
        };
    lifecycleLogRedaction =
      mkCheck "Lifecycle task runner declares checked log redaction support." lifecycleRedactionFindings
        {
          helper = "devcontainer-task-runner";
          checkName = (runtimeHelpers."devcontainer-task-runner" or { }).checkName or null;
        };
    extensionProjectionLogRedaction =
      mkCheck "VS Code extension projector declares checked log redaction support."
        projectionRedactionFindings
        {
          helper = "vscode-extension-projector";
          checkName = (runtimeHelpers."vscode-extension-projector" or { }).checkName or null;
        };
    shellInitSideEffects =
      mkCheck "Shell init does not auto-run package managers or obvious mutating commands."
        shellSideEffectFindings
        {
          scannedSources = [ "shellInit" ];
          autoRun = {
            npxFindingCount = builtins.length npxFindings;
            uvxFindingCount = builtins.length uvxFindings;
          };
          rules = map (rule: rule.name) sideEffectPredicates;
        };
  };

  allFindings = lib.concatLists (map (check: check.evidence.findings) (builtins.attrValues checks));
in
{
  report = {
    image = config.devcontainer.image.name;
    checks = checks;
    findings = allFindings;
  };
}
