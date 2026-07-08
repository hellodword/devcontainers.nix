{
  lib,
  images,
  contractLib,
  ...
}:

let
  requiredLinks = [
    "/bin"
    "/include"
    "/lib"
    "/lib64"
    "/libexec"
    "/share"
    "/etc"
  ];
  requiredLocaleEnv = {
    LANG = "en_US.UTF-8";
    LANGUAGE = "en_US:en";
    XDG_CONFIG_DIRS = "/etc/xdg";
    XDG_DATA_DIRS = "/usr/local/share:/usr/share";
  };
  requiredXdgEnv = {
    XDG_CONFIG_HOME = "/home/vscode/.config";
    XDG_CACHE_HOME = "/home/vscode/.cache";
    XDG_DATA_HOME = "/home/vscode/.local/share";
    XDG_STATE_HOME = "/home/vscode/.local/state";
    XDG_RUNTIME_DIR = "/run/user/1000";
  };
  requiredNixpkgsEnv = {
    NIXPKGS_CONFIG = "/etc/nixpkgs/config.nix";
    NIXPKGS_ALLOW_UNFREE = "1";
    NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM = "1";
    NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE = "1";
  };
  requiredCoreEnv = {
    DO_NOT_TRACK = "true";
    NIX_PAGER = "cat";
    NIX_PATH = "nixpkgs=/usr/share/devcontainer/nixpkgs";
  };
  requiredCaEnv = [
    "SSL_CERT_FILE"
    "NIX_SSL_CERT_FILE"
    "CURL_CA_BUNDLE"
    "GIT_SSL_CAINFO"
  ];
  requiredLibraryEnv = [
    "PKG_CONFIG_PATH"
    "CMAKE_PREFIX_PATH"
    "NIXPKGS_CMAKE_PREFIX_PATH"
    "CPATH"
    "LIBRARY_PATH"
    "NIX_CFLAGS_COMPILE"
    "NIX_LDFLAGS"
  ];
  sourceEntry = image: name: image.env.containerEnvSources.${name} or { };
  sourcesFor = image: name: (sourceEntry image name).sources or [ ];
  hasSource =
    image: name: source:
    builtins.elem source (sourcesFor image name);
  envMatches =
    expected: env:
    lib.all (name: (env.${name} or null) == expected.${name}) (builtins.attrNames expected);
  envHasSource =
    expected: image: source:
    lib.all (name: hasSource image name source) (builtins.attrNames expected);
  namesWithUnexpandedHomeOrXdg =
    env:
    builtins.filter (
      name:
      let
        value = env.${name};
      in
      builtins.isString value && (lib.hasInfix "$HOME" value || lib.hasInfix "$XDG_" value)
    ) (builtins.attrNames env);
  expectedRuntimeProfile = "/home/vscode/.local/share/devpkg/runtime-libraries/profile";
  expectedBuildProfile = "/home/vscode/.local/share/devpkg/build-libraries/profile";
  expectedWorkspacePathSegments = [
    "$WORKSPACE/.devcontainer/bin"
    "$WORKSPACE/node_modules/.bin"
    "$WORKSPACE/.venv/bin"
  ];
  perImage = lib.mapAttrsToList (
    name: image:
    let
      env = image.env.containerEnv;
      environment = image.environment.report;
      metadataEnv = image.metadata.mergedPreview.containerEnv or { };
      lateBoundEnv = image.env.lateBoundContainerEnv or { };
      pathSegments = lib.splitString ":" (env.PATH or "");
      staticPathSegments = image.env.staticPathSegments or pathSegments;
      runtimePathSegments = image.env.runtimePathSegments or (image.env.pathSegments or pathSegments);
      workspacePathSegments = image.env.workspace.pathSegments or [ ];
      libraries = image.libraries.report;
      libraryPresets = libraries.settings.presets or [ ];
      profileLibraryPresets = image.profiles.libraryPresets;
      fhs = image.fhsRuntime;
      nixLdLibraryPathInputs = fhs.nixLdLibraryPathInputs or [ ];
      hasNixLdLibraryInputRole =
        role: lib.any (entry: (entry.role or null) == role) nixLdLibraryPathInputs;
      hasNixLdLibraryInputStorePath =
        storePath: lib.any (entry: (entry.storePath or null) == storePath) nixLdLibraryPathInputs;
      hasGoProfile = builtins.elem "language/go" image.profiles.ids;
      hasRustProfile = builtins.elem "language/rust" image.profiles.ids;
      shellAliases = image.shell.report.aliases or { };
      gobuildAlias = shellAliases."gobuild-small" or { };
      missingEnvironmentLinks = builtins.filter (
        path: !(builtins.elem path (environment.pathsToLink or [ ]))
      ) requiredLinks;
      checks = {
        environmentReportPresent = environment != { };
        requiredLinksPresent = missingEnvironmentLinks == [ ];
        extraOutputsIsList = builtins.isList (environment.extraOutputsToInstall or null);
        editorConfigured = builtins.hasAttr "EDITOR" (environment.variables or { });
        pathSourceDetailsPresent = builtins.hasAttr "PATH" image.env.containerEnvSources;
        pathEntriesPresent = ((sourceEntry image "PATH").pathEntries or [ ]) != [ ];
        editorSourceDetailsPresent = sourcesFor image "EDITOR" != [ ];
        metadataDoesNotPublishPath =
          !(builtins.hasAttr "PATH" (image.metadata.mergedPreview.containerEnv or { }));
        metadataEditorMatches =
          ((image.metadata.mergedPreview.containerEnv or { }).EDITOR or null) == (env.EDITOR or null);
        noLdLibraryPath = !(builtins.hasAttr "LD_LIBRARY_PATH" env);
        noGlobalFontconfigFile = !(builtins.hasAttr "FONTCONFIG_FILE" env);
        localeValues = envMatches requiredLocaleEnv env;
        localeSources = envHasSource requiredLocaleEnv image "core.locale";
        localeArchivePath =
          builtins.isString (env.LOCALE_ARCHIVE or null)
          && lib.hasInfix "glibc-locales" env.LOCALE_ARCHIVE
          && lib.hasSuffix "/lib/locale/locale-archive" env.LOCALE_ARCHIVE;
        localeArchiveSource = hasSource image "LOCALE_ARCHIVE" "core.locale";
        noLcAll = !(builtins.hasAttr "LC_ALL" env);
        tzdir = (env.TZDIR or null) == "/etc/zoneinfo";
        xdgValues = envMatches requiredXdgEnv env;
        nixpkgsValues = envMatches requiredNixpkgsEnv env;
        nixpkgsSources = envHasSource requiredNixpkgsEnv image "core.env";
        coreEnvValues = envMatches requiredCoreEnv env;
        coreEnvSources = envHasSource requiredCoreEnv image "core.env";
        workspaceLateBound = image.env.workspace.lateBound or false;
        workspaceNotInStaticEnv = !(builtins.hasAttr "WORKSPACE" env);
        workspaceInMetadata = (metadataEnv.WORKSPACE or null) == "\${containerWorkspaceFolder}";
        staticPathMatchesSegments = (env.PATH or "") == lib.concatStringsSep ":" staticPathSegments;
        workspacePathSegmentsLateBound = workspacePathSegments == expectedWorkspacePathSegments;
        workspacePathSegmentsOmittedFromStatic =
          lib.intersectLists workspacePathSegments staticPathSegments == [ ];
        runtimePathCarriesWorkspace = lib.all (
          segment: builtins.elem segment runtimePathSegments
        ) workspacePathSegments;
        devpkgNixpkgsRef =
          builtins.isString (env.DEVPKG_NIXPKGS_REF or null)
          && lib.hasPrefix "path:/nix/store/" env.DEVPKG_NIXPKGS_REF
          && lib.hasSuffix "-source" env.DEVPKG_NIXPKGS_REF;
        devpkgNixpkgsRefSource = hasSource image "DEVPKG_NIXPKGS_REF" "core.env";
        devpkgSystem = contractLib.nonEmptyString (env.DEVPKG_SYSTEM or null);
        devpkgSystemSource = hasSource image "DEVPKG_SYSTEM" "core.env";
        devpkgCacheKey = contractLib.nonEmptyString (env.DEVPKG_NIXPKGS_CACHE_KEY or null);
        devpkgCacheKeySource = hasSource image "DEVPKG_NIXPKGS_CACHE_KEY" "core.env";
        noHomeOrXdgReferences = namesWithUnexpandedHomeOrXdg env == [ ];
        noUsrMergeBinInPath = !(builtins.elem "/bin" pathSegments);
        usrLocalBeforeUsr =
          builtins.elem "/usr/local/bin" pathSegments
          && builtins.elem "/usr/bin" pathSegments
          &&
            (lib.lists.findFirstIndex (segment: segment == "/usr/local/bin") null pathSegments)
            < (lib.lists.findFirstIndex (segment: segment == "/usr/bin") null pathSegments);
        nixLdMatchesRealLoader = (env.NIX_LD or null) == fhs.realGlibcLoader;
        metadataNixLdMatches =
          ((image.metadata.mergedPreview.containerEnv or { }).NIX_LD or null) == fhs.realGlibcLoader;
        nixLdLibraryPathMatches =
          (env.NIX_LD_LIBRARY_PATH or null) == (fhs.nixLdEnv.NIX_LD_LIBRARY_PATH or null);
        nixLdLibraryPathHasRuntimeLibs =
          hasNixLdLibraryInputRole "glibc" && hasNixLdLibraryInputRole "gcc-lib";
        libraryProfilesExpanded =
          (libraries.runtime.dynamicProfile or null) == expectedRuntimeProfile
          && (libraries.build.dynamicProfile or null) == expectedBuildProfile;
        libraryPresetsDeduped =
          builtins.length libraryPresets == builtins.length (lib.unique libraryPresets);
        libraryPresetsMatchProfiles = contractLib.sameSet libraryPresets profileLibraryPresets;
        dynamicProfileEnv =
          (env.DEVPKG_RUNTIME_LIBRARY_PROFILE or null) == expectedRuntimeProfile
          && (env.DEVPKG_BUILD_LIBRARY_PROFILE or null) == expectedBuildProfile;
        nixLdHasDynamicProfiles =
          hasNixLdLibraryInputRole "runtime-dynamic-profile"
          && hasNixLdLibraryInputStorePath "${expectedRuntimeProfile}/lib"
          && hasNixLdLibraryInputRole "build-dynamic-profile"
          && hasNixLdLibraryInputStorePath "${expectedBuildProfile}/lib";
        libraryEnvPresent = lib.all (envName: builtins.hasAttr envName env) requiredLibraryEnv;
        libraryEnvSources = lib.all (
          envName: hasSource image envName "compiler.libraries.core"
        ) requiredLibraryEnv;
        goLibraryContract =
          if hasGoProfile then
            builtins.elem "cgo" libraryPresets
            && builtins.hasAttr "CGO_CFLAGS" env
            && builtins.hasAttr "CGO_LDFLAGS" env
            && hasSource image "CGO_CFLAGS" "compiler.libraries.preset.cgo"
            && hasSource image "CGO_LDFLAGS" "compiler.libraries.preset.cgo"
            && (gobuildAlias.command or null) == ''go build -trimpath -ldflags "-s -w -buildid="''
            && builtins.elem "language/go" (gobuildAlias.origins or [ ])
          else
            !(builtins.elem "cgo" libraryPresets) && !(builtins.hasAttr "gobuild-small" shellAliases);
        rustLibraryContract =
          if hasRustProfile then
            builtins.elem "rust-bindgen" libraryPresets
            && builtins.hasAttr "BINDGEN_EXTRA_CLANG_ARGS" env
            && hasSource image "BINDGEN_EXTRA_CLANG_ARGS" "compiler.libraries.preset.rust-bindgen"
            && !(builtins.hasAttr "CARGO_TARGET_DIR" env)
            && (lateBoundEnv.CARGO_TARGET_DIR or null) == "$WORKSPACE/target"
            && (metadataEnv.CARGO_TARGET_DIR or null) == "\${containerWorkspaceFolder}/target"
          else
            !(builtins.elem "rust-bindgen" libraryPresets);
        fhsEnvSources = lib.all (envName: hasSource image envName "compiler.fhs-runtime.nix-ld") [
          "NIX_LD"
          "NIX_LD_LIBRARY_PATH"
        ];
        caEnvValues = lib.all (
          envName: (env.${envName} or null) == "/etc/ssl/certs/ca-certificates.crt"
        ) requiredCaEnv;
        caEnvSources = lib.all (
          envName: hasSource image envName "compiler.fhs-runtime.ca-certificates"
        ) requiredCaEnv;
      };
    in
    {
      inherit name checks;
      details = {
        inherit missingEnvironmentLinks;
        pathSegments = pathSegments;
        runtimePathSegments = runtimePathSegments;
        unexpandedEnvNames = namesWithUnexpandedHomeOrXdg env;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-env = contractLib.mkAssertedJsonCheck "contracts-reports-env" [ allValid ] {
    images = perImage;
  };
}
