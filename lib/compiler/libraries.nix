{ lib }:
{
  config,
  compiledEnvironment ? {
    variables = { };
  },
  compiledProfiles ? {
    libraryPresets = [ ];
  },
}:
let
  envUtils = import ./env-utils.nix { inherit lib; };
  libraryUtils = import ../library-utils.nix { inherit lib; };
  cfg = config.devcontainer.libraries;
  presets = lib.unique (compiledProfiles.libraryPresets ++ cfg.presets);

  runtimeOutputs = libraryUtils.uniqueDrvs (
    (map libraryUtils.runtimeOutput cfg.runtime) ++ (map libraryUtils.runtimeOutput cfg.build)
  );
  buildOutputs = libraryUtils.uniqueDrvs (lib.concatMap libraryUtils.buildOutputs cfg.build);
  buildLayerOutputs = libraryUtils.withoutDrvs runtimeOutputs buildOutputs;

  expandedBaseEnv = envUtils.expandEnv {
    env = compiledEnvironment.variables;
    scope = "library base environment";
  };
  runtimeProfile = envUtils.expandValue {
    env = expandedBaseEnv;
    value = cfg.dynamicRuntimeProfile;
  };
  buildProfile = envUtils.expandValue {
    env = expandedBaseEnv;
    value = cfg.dynamicBuildProfile;
  };

  runtimeStorePaths = map libraryUtils.displayPathString runtimeOutputs;
  buildStorePaths = map libraryUtils.displayPathString buildOutputs;
  buildLayerStorePaths = map libraryUtils.displayPathString buildLayerOutputs;

  runtimeDynamicLibraryPathEntries = [
    "${runtimeProfile}/lib"
    "${buildProfile}/lib"
  ];
  runtimeLdLibraryPathEntries =
    (map (path: "${path}/lib") runtimeStorePaths) ++ runtimeDynamicLibraryPathEntries;

  buildPrefixes = buildStorePaths ++ [ buildProfile ];
  includeEntries = (map (path: "${path}/include") buildStorePaths) ++ [ "${buildProfile}/include" ];
  buildLibraryPathEntries =
    lib.concatMap (path: [
      "${path}/lib"
      "${path}/lib64"
    ]) buildStorePaths
    ++ [
      "${buildProfile}/lib"
      "${buildProfile}/lib64"
    ];
  pkgConfigEntries =
    lib.concatMap (path: [
      "${path}/lib/pkgconfig"
      "${path}/share/pkgconfig"
    ]) buildStorePaths
    ++ [
      "${buildProfile}/lib/pkgconfig"
      "${buildProfile}/share/pkgconfig"
    ];
  cmakePrefixEntries = buildPrefixes;
  aclocalEntries = map (path: "${path}/share/aclocal") buildPrefixes;
  baseXdgDataEntries =
    if expandedBaseEnv ? XDG_DATA_DIRS then lib.splitString ":" expandedBaseEnv.XDG_DATA_DIRS else [ ];
  xdgDataEntries = (map (path: "${path}/share") buildPrefixes) ++ baseXdgDataEntries;
  gioModuleEntries = map (path: "${path}/lib/gio/modules") buildPrefixes;
  giTypelibEntries = map (path: "${path}/lib/girepository-1.0") buildPrefixes;
  gstPluginEntries = map (path: "${path}/lib/gstreamer-1.0") buildPrefixes;
  qtPluginEntries = lib.concatMap (path: [
    "${path}/lib/qt-6/plugins"
    "${path}/lib/qt-5/plugins"
  ]) buildPrefixes;
  qmlEntries = lib.concatMap (path: [
    "${path}/lib/qt-6/qml"
    "${path}/lib/qt-5/qml"
  ]) buildPrefixes;

  colon = entries: lib.concatStringsSep ":" (lib.unique entries);
  space = entries: lib.concatStringsSep " " entries;
  includeFlags = map (path: "-I${path}") includeEntries;
  systemIncludeFlags = map (path: "-isystem ${path}") includeEntries;
  libraryFlags = map (path: "-L${path}") buildLibraryPathEntries;

  coreEnv = {
    DEVPKG_RUNTIME_LIBRARY_PROFILE = runtimeProfile;
    DEVPKG_BUILD_LIBRARY_PROFILE = buildProfile;
    PKG_CONFIG_PATH = colon pkgConfigEntries;
    CMAKE_PREFIX_PATH = colon cmakePrefixEntries;
    NIXPKGS_CMAKE_PREFIX_PATH = colon cmakePrefixEntries;
    CPATH = colon includeEntries;
    LIBRARY_PATH = colon buildLibraryPathEntries;
  }
  // lib.optionalAttrs cfg.ccWrapperFlags {
    NIX_CFLAGS_COMPILE = space systemIncludeFlags;
    NIX_LDFLAGS = space libraryFlags;
  }
  // lib.optionalAttrs cfg.exportLdLibraryPath {
    LD_LIBRARY_PATH = colon runtimeLdLibraryPathEntries;
  };

  presetEnvByName = {
    autotools = {
      CPPFLAGS = space includeFlags;
      LDFLAGS = space libraryFlags;
      ACLOCAL_PATH = colon aclocalEntries;
    };
    gtk = {
      XDG_DATA_DIRS = colon xdgDataEntries;
      GIO_EXTRA_MODULES = colon gioModuleEntries;
    };
    "gobject-introspection" = {
      GI_TYPELIB_PATH = colon giTypelibEntries;
      XDG_DATA_DIRS = colon xdgDataEntries;
    };
    gstreamer = {
      GST_PLUGIN_SYSTEM_PATH_1_0 = colon gstPluginEntries;
    };
    qt = {
      QT_PLUGIN_PATH = colon qtPluginEntries;
      QML2_IMPORT_PATH = colon qmlEntries;
      XDG_DATA_DIRS = colon xdgDataEntries;
    };
    cgo = {
      CGO_CFLAGS = space includeFlags;
      CGO_LDFLAGS = space libraryFlags;
    };
    "rust-bindgen" = {
      BINDGEN_EXTRA_CLANG_ARGS = space systemIncludeFlags;
    };
  };
  missingPresetEnv = builtins.filter (preset: !(builtins.hasAttr preset presetEnvByName)) presets;

  presetEnvEntries =
    if missingPresetEnv != [ ] then
      builtins.throw (
        "devcontainer.libraries presets missing generated env definitions: "
        + lib.concatStringsSep ", " missingPresetEnv
      )
    else
      map (preset: {
        inherit preset;
        env = presetEnvByName.${preset};
      }) presets;
  presetsEnv = lib.foldl' (acc: entry: acc // entry.env) { } presetEnvEntries;

  envContainer = coreEnv // presetsEnv;
  coreOrigins = lib.mapAttrs (_: _: [ "compiler.libraries.core" ]) coreEnv;
  presetOrigins = lib.foldl' (
    acc: entry:
    lib.foldl' (
      inner: name:
      inner
      // {
        ${name} = lib.unique ((inner.${name} or [ ]) ++ [ "compiler.libraries.preset.${entry.preset}" ]);
      }
    ) acc (builtins.attrNames entry.env)
  ) { } presetEnvEntries;
in
{
  runtime = {
    configuredPackages = map libraryUtils.packageReport cfg.runtime;
    effectivePackages = map libraryUtils.packageReport (cfg.runtime ++ cfg.build);
    outputPaths = runtimeOutputs;
    storePaths = runtimeStorePaths;
    dynamicProfile = runtimeProfile;
    dynamicLibraryPathEntries = runtimeDynamicLibraryPathEntries;
    nixLdLibraryPathEntries = runtimeLdLibraryPathEntries;
  };
  build = {
    configuredPackages = map libraryUtils.packageReport cfg.build;
    outputPaths = buildOutputs;
    layerOutputPaths = buildLayerOutputs;
    storePaths = buildStorePaths;
    layerStorePaths = buildLayerStorePaths;
    dynamicProfile = buildProfile;
    prefixes = buildPrefixes;
    includeEntries = includeEntries;
    libraryPathEntries = buildLibraryPathEntries;
    pkgConfigEntries = pkgConfigEntries;
    cmakePrefixEntries = cmakePrefixEntries;
  };
  imagePaths = runtimeOutputs ++ buildLayerOutputs;
  settings = {
    exportLdLibraryPath = cfg.exportLdLibraryPath;
    ccWrapperFlags = cfg.ccWrapperFlags;
    presets = presets;
  };
  env = {
    container = envContainer;
  };
  envOrigins = {
    container = coreOrigins // presetOrigins;
    remote = { };
    shell = { };
  };
  report = {
    runtime = {
      configuredPackages = map libraryUtils.packageReport cfg.runtime;
      effectivePackages = map libraryUtils.packageReport (cfg.runtime ++ cfg.build);
      storePaths = runtimeStorePaths;
      dynamicProfile = runtimeProfile;
      dynamicLibraryPathEntries = runtimeDynamicLibraryPathEntries;
    };
    build = {
      configuredPackages = map libraryUtils.packageReport cfg.build;
      storePaths = buildStorePaths;
      layerStorePaths = buildLayerStorePaths;
      dynamicProfile = buildProfile;
      prefixes = buildPrefixes;
      includeEntries = includeEntries;
      libraryPathEntries = buildLibraryPathEntries;
      pkgConfigEntries = pkgConfigEntries;
      cmakePrefixEntries = cmakePrefixEntries;
    };
    settings = {
      exportLdLibraryPath = cfg.exportLdLibraryPath;
      ccWrapperFlags = cfg.ccWrapperFlags;
      presets = presets;
    };
    generatedEnv = envContainer;
  };
}
