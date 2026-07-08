{
  lib,
  pkgs,
  system,
}:
{
  config,
  compiledLibraries ? {
    runtime = {
      outputPaths = [ ];
      dynamicLibraryPathEntries = [ ];
    };
  },
}:
let
  caCertificates = import ../ca-certificates.nix { inherit lib pkgs; };
  cfg = config.devcontainer.compat.fhsRuntime;
  nixLdCfg = config.programs.nix-ld;
  pkiCfg = config.security.pki;
  displayPathString = path: builtins.unsafeDiscardStringContext (toString path);
  compiledRuntime = compiledLibraries.runtime or { };
  compiledBuild = compiledLibraries.build or { };
  currentDynamicLoader =
    if system == "x86_64-linux" then
      nixLdCfg.dynamicLoader.x86_64.path
    else if system == "aarch64-linux" then
      nixLdCfg.dynamicLoader.aarch64.path
    else
      null;
  dynamicLoaderFile =
    if system == "x86_64-linux" then
      "ld-linux-x86-64.so.2"
    else if system == "aarch64-linux" then
      "ld-linux-aarch64.so.1"
    else
      null;
  dynamicLoaderDirectory = if system == "x86_64-linux" then "lib64" else "lib";
  realGlibcLoader =
    if currentDynamicLoader == null then
      null
    else
      "${glibcLoaderRoot}/${dynamicLoaderDirectory}/${dynamicLoaderFile}";
  dynamicLoaderSource =
    if currentDynamicLoader == null then
      null
    else if nixLdCfg.enable then
      "${nixLdCfg.package}/bin/nix-ld"
    else
      realGlibcLoader;
  nixLdEnabled = cfg.enable && nixLdCfg.enable && currentDynamicLoader != null;
  mkPackageLibraryPathInput = role: package: {
    inherit role;
    name = package.name or (builtins.baseNameOf (displayPathString package));
    storePath = displayPathString package;
    libraryPath = "${package}/lib";
  };
  dynamicLibraryPathRole =
    entry:
    if
      (compiledRuntime.dynamicProfile or null) != null && entry == "${compiledRuntime.dynamicProfile}/lib"
    then
      "runtime-dynamic-profile"
    else if
      (compiledBuild.dynamicProfile or null) != null && entry == "${compiledBuild.dynamicProfile}/lib"
    then
      "build-dynamic-profile"
    else
      "dynamic-profile";
  dynamicLibraryPathName =
    role:
    if role == "runtime-dynamic-profile" then
      "runtime"
    else if role == "build-dynamic-profile" then
      "build"
    else
      "dynamic";
  mkDynamicLibraryPathInput =
    entry:
    let
      role = dynamicLibraryPathRole entry;
    in
    {
      inherit role;
      name = dynamicLibraryPathName role;
      storePath = entry;
      libraryPath = entry;
    };
  nixLdLibraryPathInputsWithPath = [
    (mkPackageLibraryPathInput "glibc" pkgs.glibc)
    (mkPackageLibraryPathInput "gcc-lib" pkgs.stdenv.cc.cc.lib)
  ]
  ++ (map (mkPackageLibraryPathInput "nix-ld-library") nixLdCfg.libraries)
  ++ (map (mkPackageLibraryPathInput "compiled-runtime-library") (compiledRuntime.outputPaths or [ ]))
  ++ (map mkDynamicLibraryPathInput (compiledRuntime.dynamicLibraryPathEntries or [ ]));
  nixLdLibraryPathInputs = lib.optionals nixLdEnabled (
    map (entry: removeAttrs entry [ "libraryPath" ]) nixLdLibraryPathInputsWithPath
  );
  nixLdLibraryPath = lib.concatStringsSep ":" (
    lib.optionals nixLdEnabled (map (entry: entry.libraryPath) nixLdLibraryPathInputsWithPath)
  );
  nixLdEnv = lib.optionalAttrs nixLdEnabled {
    NIX_LD = realGlibcLoader;
    NIX_LD_LIBRARY_PATH = nixLdLibraryPath;
  };
  certBundleTarget = caCertificates.bundleTarget;
  caCertificatesEnabled = cfg.enable && pkiCfg.installCACerts;
  caCertificatesRoot = caCertificates.mkRoot pkiCfg.package;
  certBundleSource = "${caCertificatesRoot}${certBundleTarget}";
  caCertificatesEnv = lib.optionalAttrs caCertificatesEnabled {
    SSL_CERT_FILE = certBundleTarget;
    NIX_SSL_CERT_FILE = certBundleTarget;
    CURL_CA_BUNDLE = certBundleTarget;
    GIT_SSL_CAINFO = certBundleTarget;
  };
  glibcLoaderRoot = pkgs.runCommand "devcontainer-glibc-loader" { } ''
    mkdir -p "$out/${dynamicLoaderDirectory}"
    if [ -e ${pkgs.glibc}/${dynamicLoaderDirectory}/${dynamicLoaderFile} ]; then
      ln -s ${pkgs.glibc}/${dynamicLoaderDirectory}/${dynamicLoaderFile} "$out/${dynamicLoaderDirectory}/${dynamicLoaderFile}"
    elif [ -e ${pkgs.glibc}/lib/${dynamicLoaderFile} ]; then
      ln -s ${pkgs.glibc}/lib/${dynamicLoaderFile} "$out/${dynamicLoaderDirectory}/${dynamicLoaderFile}"
    else
      echo "glibc dynamic loader not found" >&2
      exit 1
    fi
  '';
  emptyScopedAttrs = {
    container = { };
    remote = { };
    shell = { };
  };
  baseSymlinks = [
    {
      target = "/bin/bash";
      source = "${pkgs.bashInteractive}/bin/bash";
    }
    {
      target = "/usr/bin/bash";
      source = "${pkgs.bashInteractive}/bin/bash";
    }
    {
      target = "/bin/sh";
      source = "${pkgs.bashInteractive}/bin/sh";
    }
    {
      target = "/usr/bin/sh";
      source = "${pkgs.bashInteractive}/bin/sh";
    }
    {
      target = "/usr/bin/env";
      source = "${pkgs.coreutils}/bin/env";
    }
    {
      target = "/usr/bin/tar";
      source = "${pkgs.gnutar}/bin/tar";
    }
    {
      target = "/usr/bin/gzip";
      source = "${pkgs.gzip}/bin/gzip";
    }
    {
      target = "/usr/bin/sed";
      source = "${pkgs.gnused}/bin/sed";
    }
    {
      target = "/usr/bin/grep";
      source = "${pkgs.gnugrep}/bin/grep";
    }
    {
      target = "/usr/bin/curl";
      source = "${pkgs.curl}/bin/curl";
    }
    {
      target = "/usr/bin/wget";
      source = "${pkgs.wget}/bin/wget";
    }
    {
      target = "/usr/bin/git";
      source = "${pkgs.git}/bin/git";
    }
  ];
  dynamicLoaderSymlinks = lib.optionals (currentDynamicLoader != null) [
    {
      target = currentDynamicLoader;
      source = dynamicLoaderSource;
      sourceRole = if nixLdCfg.enable then "nix-ld" else "glibc-loader";
    }
    {
      target = "/usr/lib/libc.so.6";
      source = "${pkgs.glibc}/lib/libc.so.6";
      sourceRole = "glibc";
    }
    {
      target = "/usr/lib/libstdc++.so.6";
      source = "${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6";
      sourceRole = "gcc-lib";
    }
  ];
in
{
  enabled = cfg.enable;
  dynamicLoaderMode =
    if !cfg.enable then
      null
    else if nixLdCfg.enable then
      "nix-ld"
    else
      "glibc";
  realGlibcLoader = if cfg.enable then realGlibcLoader else null;
  nixLdEnv = nixLdEnv;
  nixLdLibraryPathInputs = nixLdLibraryPathInputs;
  caCertificates = lib.optionalAttrs caCertificatesEnabled {
    bundle = certBundleTarget;
    root = "${caCertificatesRoot}";
    source = certBundleSource;
  };
  env =
    if cfg.enable then
      emptyScopedAttrs
      // {
        container = nixLdEnv // caCertificatesEnv;
      }
    else
      emptyScopedAttrs;
  envOrigins =
    if cfg.enable then
      {
        container =
          lib.mapAttrs (
            name: _:
            if
              name == "NIX_LD_LIBRARY_PATH" && (compiledLibraries.runtime.dynamicLibraryPathEntries or [ ]) != [ ]
            then
              [
                "compiler.fhs-runtime.nix-ld"
                "compiler.libraries.runtime"
              ]
            else
              [ "compiler.fhs-runtime.nix-ld" ]
          ) nixLdEnv
          // lib.mapAttrs (_: _: [ "compiler.fhs-runtime.ca-certificates" ]) caCertificatesEnv;
        remote = { };
        shell = { };
      }
    else
      emptyScopedAttrs;
  symlinks = lib.optionals cfg.enable (baseSymlinks ++ dynamicLoaderSymlinks);
}
