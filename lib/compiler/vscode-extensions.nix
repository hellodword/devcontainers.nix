{
  lib,
  pkgs,
}:
{
  config,
  compiledProfiles ? {
    extensions = { };
    extensionIds = [ ];
  },
}:
let
  hashString = value: builtins.hashString "sha256" value;
  displayPathString = path: builtins.unsafeDiscardStringContext (toString path);
  preinstall = config.devcontainer.vscode.preinstall;
  artifactModes = if preinstall.enable then preinstall.artifacts.modes else [ ];
  includeProjection = builtins.elem "projection" artifactModes;
  includeArchive = builtins.elem "archive" artifactModes;
  projectionEnabled = includeProjection && preinstall.projection.enable;
  extensionSets = {
    vscode-marketplace-release = pkgs.vscode-marketplace-release;
    open-vsx-release = pkgs.open-vsx-release;
  };
  attrForId =
    id:
    let
      parts = lib.splitString "." id;
      publisher = lib.toLower (builtins.head parts);
      name = lib.toLower (lib.concatStringsSep "." (builtins.tail parts));
    in
    [
      publisher
      name
    ];
  resolveExtension =
    id: sourcePreference:
    let
      attrPath = attrForId id;
      marketplace = lib.attrByPath attrPath null extensionSets.vscode-marketplace-release;
      openVsx = lib.attrByPath attrPath null extensionSets.open-vsx-release;
      marketplaceResolved =
        if marketplace != null then
          {
            package = marketplace;
            source = "nix-vscode-extensions.vscode-marketplace-release";
          }
        else
          null;
      openVsxResolved =
        if openVsx != null then
          {
            package = openVsx;
            source = "nix-vscode-extensions.open-vsx-release";
          }
        else
          null;
      candidates =
        if sourcePreference == "open-vsx-first" then
          [
            openVsxResolved
            marketplaceResolved
          ]
        else
          [
            marketplaceResolved
            openVsxResolved
          ];
      resolved = lib.findFirst (candidate: candidate != null) null candidates;
    in
    if resolved != null then
      resolved
    else
      builtins.throw "VS Code extension ${id} was not found in nix-vscode-extensions release sets";
  sourceRefFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
      urls = if srcDrv != null && srcDrv ? urls then srcDrv.urls else [ ];
    in
    if urls != [ ] then
      builtins.head urls
    else
      "nix-store:${displayPathString (extensionPackage.src or extensionPackage)}";
  sourceHashFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
    in
    if srcDrv != null && srcDrv ? outputHash then
      srcDrv.outputHash
    else
      hashString (displayPathString (extensionPackage.src or extensionPackage));
  sourceArchiveNameFor =
    extensionPackage:
    let
      srcDrv = extensionPackage.drvAttrs.src or null;
    in
    if srcDrv != null && srcDrv ? name then
      srcDrv.name
    else
      builtins.baseNameOf (displayPathString (extensionPackage.src or extensionPackage));
  mkExtension =
    metadata:
    let
      id = metadata.id;
      resolved = resolveExtension id metadata.sourcePreference;
      extensionPackage = resolved.package;
      passthru = extensionPackage.passthru or { };
      parts = lib.splitString "." id;
      requestedPublisher = builtins.head parts;
      requestedName = lib.concatStringsSep "." (builtins.tail parts);
      publisher =
        if passthru ? vscodeExtPublisher then passthru.vscodeExtPublisher else requestedPublisher;
      name = if passthru ? vscodeExtName then passthru.vscodeExtName else requestedName;
      uniqueId =
        if passthru ? vscodeExtUniqueId then passthru.vscodeExtUniqueId else "${publisher}.${name}";
      native = metadata.native;
      required = metadata.required;
      bucket = metadata.bucket;
      pathSegment = uniqueId;
      vsixName = "${builtins.replaceStrings [ "." ] [ "-" ] uniqueId}.vsix";
      extensionVersion = extensionPackage.version or "unknown";
      sourceRef = sourceRefFor extensionPackage;
      sourceHash = sourceHashFor extensionPackage;
      sourceLock = {
        ref = sourceRef;
        sha256 = sourceHash;
        manifestFingerprint = hashString "${uniqueId}:${extensionVersion}:${sourceHash}:manifest";
        vsixSha256 = sourceHash;
        archiveName = sourceArchiveNameFor extensionPackage;
      };
      projection =
        if metadata.projectionOverride != null then
          metadata.projectionOverride
        else if native then
          "copy-if-needed-with-fhs"
        else
          "symlink";
      projectionPath = "${preinstall.artifacts.projectionPath}/${pathSegment}";
      archivePath = "${preinstall.artifacts.archivePath}/${vsixName}";
      public = {
        inherit
          id
          native
          required
          bucket
          publisher
          name
          uniqueId
          projection
          ;
        version = extensionVersion;
        source = resolved.source;
        path = if includeProjection then projectionPath else null;
        archivePath = if includeArchive then archivePath else null;
        artifacts = {
          modes = artifactModes;
          projection = {
            enabled = includeProjection;
            path = if includeProjection then projectionPath else null;
          };
          archive = {
            enabled = includeArchive;
            path = if includeArchive then archivePath else null;
            name = vsixName;
            sourcePath = displayPathString (extensionPackage.src or extensionPackage);
          };
        };
        companionTools = metadata.companionTools;
        sourcePreference = metadata.sourcePreference;
        origins = metadata.origins;
        notes = metadata.notes;
        sourceLock = sourceLock;
        validation = {
          nativeBinaries = native;
          fhsRuntime = config.devcontainer.vscode.preinstall.validation.fhsRuntime;
          noNetworkDuringProjection =
            config.devcontainer.vscode.preinstall.validation.noNetworkDuringProjection;
          strategy = projection;
        };
      };
    in
    {
      inherit public;
      projectionImage = {
        inherit id projection;
        path = projectionPath;
        sourcePath = "${extensionPackage}/share/vscode/extensions/${uniqueId}";
      };
      archiveImage = {
        inherit id;
        path = archivePath;
        sourcePath = extensionPackage.src or extensionPackage;
      };
      index = {
        inherit id projection required;
        path = projectionPath;
      };
    };
  compiledExtensions = map (
    id: mkExtension compiledProfiles.extensions.${id}
  ) compiledProfiles.extensionIds;
in
{
  extensions = map (extension: extension.public) compiledExtensions;
  projectionExtensions =
    if projectionEnabled then map (extension: extension.index) compiledExtensions else [ ];
  projectionArtifacts =
    if includeProjection then map (extension: extension.projectionImage) compiledExtensions else [ ];
  archiveArtifacts =
    if includeArchive then map (extension: extension.archiveImage) compiledExtensions else [ ];
  projectionTargets = if projectionEnabled then preinstall.projection.targets else [ ];
  artifacts = {
    modes = artifactModes;
    projectionEnabled = projectionEnabled;
    archiveEnabled = includeArchive;
    projectionPath = preinstall.artifacts.projectionPath;
    archivePath = preinstall.artifacts.archivePath;
  };
}
