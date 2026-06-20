{ lib }:
{
  config,
  compiledProfiles ? {
    packages = [ ];
    env = {
      variables = { };
      variableOrigins = { };
      remoteVariables = { };
      remoteVariableOrigins = { };
      aliases = { };
      aliasOrigins = { };
      shellInit = "";
      interactiveShellInit = "";
    };
  },
}:
let
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  valueToString =
    value:
    if builtins.isBool value then
      if value then "1" else "0"
    else if builtins.isInt value then
      toString value
    else if builtins.isList value then
      lib.concatStringsSep ":" (map valueToString value)
    else
      pathString value;
  mergedVariables = compiledProfiles.env.variables // config.environment.variables;
  mergeOrigins = lib.zipAttrsWith (_: values: lib.unique (lib.concatLists values));
  mergedVariableOrigins = mergeOrigins [
    compiledProfiles.env.variableOrigins
    config.environment.variableOrigins
  ];
  mergedRemoteEnv = compiledProfiles.env.remoteVariables // config.devcontainer.remoteEnv;
  mergedRemoteEnvOrigins = mergeOrigins [
    compiledProfiles.env.remoteVariableOrigins
    config.devcontainer.remoteEnvOrigins
  ];
  mergedShellAliases = compiledProfiles.env.aliases // config.environment.shellAliases;
  mergedShellAliasOrigins = mergeOrigins [
    compiledProfiles.env.aliasOrigins
    config.environment.shellAliasOrigins
  ];
  mergedShellInit = lib.concatStringsSep "\n" (
    builtins.filter (value: value != "") [
      config.environment.shellInit
      compiledProfiles.env.shellInit
    ]
  );
  mergedInteractiveShellInit = lib.concatStringsSep "\n" (
    builtins.filter (value: value != "") [
      config.environment.interactiveShellInit
      compiledProfiles.env.interactiveShellInit
    ]
  );
  stringVariables = lib.mapAttrs (_: valueToString) mergedVariables;
  stringRemoteEnv = lib.mapAttrs (_: valueToString) mergedRemoteEnv;
  invalidVariableNames = builtins.filter (
    name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name == null
  ) (builtins.attrNames stringVariables);
  invalidRemoteEnvNames = builtins.filter (
    name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name == null
  ) (builtins.attrNames stringRemoteEnv);
  normalizeEtcTarget =
    target: if lib.hasPrefix "/etc/" target then lib.removePrefix "/etc/" target else target;
  etcEntries = lib.mapAttrsToList (
    name: spec:
    let
      target = normalizeEtcTarget spec.target;
      targetSegments = lib.splitString "/" target;
    in
    {
      inherit name target;
      path = "/etc/${target}";
      source = spec.source;
      sourcePath = if spec.source == null then null else pathString spec.source;
      text = spec.text;
      inherit (spec) mode uid gid;
      invalidTarget =
        target == ""
        || lib.hasPrefix "/" target
        || builtins.elem ".." targetSegments
        || builtins.elem "" targetSegments;
      invalidPayload =
        (spec.text == null && spec.source == null) || (spec.text != null && spec.source != null);
    }
  ) config.environment.etc;
  invalidEtcTargets = map (entry: entry.name) (
    builtins.filter (entry: entry.invalidTarget) etcEntries
  );
  invalidEtcPayloads = map (entry: entry.name) (
    builtins.filter (entry: entry.invalidPayload) etcEntries
  );
  validatedEtcEntries =
    if invalidVariableNames != [ ] then
      throw (
        "environment.variables contains invalid variable names: "
        + lib.concatStringsSep ", " invalidVariableNames
      )
    else if invalidRemoteEnvNames != [ ] then
      throw (
        "devcontainer.remoteEnv contains invalid variable names: "
        + lib.concatStringsSep ", " invalidRemoteEnvNames
      )
    else if invalidEtcTargets != [ ] then
      throw (
        "environment.etc entries must target relative paths below /etc; invalid entries: "
        + lib.concatStringsSep ", " invalidEtcTargets
      )
    else if invalidEtcPayloads != [ ] then
      throw (
        "environment.etc entries must set exactly one of text or source; invalid entries: "
        + lib.concatStringsSep ", " invalidEtcPayloads
      )
    else
      map (
        entry:
        removeAttrs entry [
          "invalidTarget"
          "invalidPayload"
        ]
      ) etcEntries;
  packageName = drv: drv.pname or drv.name or (builtins.baseNameOf (pathString drv));
in
{
  systemPackages = lib.unique (config.environment.systemPackages ++ compiledProfiles.packages);
  packageNames = map packageName (
    lib.unique (config.environment.systemPackages ++ compiledProfiles.packages)
  );
  pathsToLink = config.environment.pathsToLink;
  extraOutputsToInstall = config.environment.extraOutputsToInstall;
  variables = stringVariables;
  variableOrigins = mergedVariableOrigins;
  remoteEnv = stringRemoteEnv;
  remoteEnvOrigins = mergedRemoteEnvOrigins;
  shellAliases = mergedShellAliases;
  shellAliasOrigins = mergedShellAliasOrigins;
  shellInit = mergedShellInit;
  interactiveShellInit = mergedInteractiveShellInit;
  etc = validatedEtcEntries;
  report = {
    packageCount = builtins.length (
      lib.unique (config.environment.systemPackages ++ compiledProfiles.packages)
    );
    packages = map packageName (
      lib.unique (config.environment.systemPackages ++ compiledProfiles.packages)
    );
    pathsToLink = config.environment.pathsToLink;
    extraOutputsToInstall = config.environment.extraOutputsToInstall;
    variables = stringVariables;
    remoteEnv = stringRemoteEnv;
    shellAliases = mergedShellAliases;
    etc = map (entry: {
      inherit (entry)
        name
        target
        path
        mode
        uid
        gid
        sourcePath
        ;
      hasText = entry.text != null;
    }) validatedEtcEntries;
  };
}
