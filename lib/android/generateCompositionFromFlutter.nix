pkgs: flutterPkg:
let

  splitString = sep: s: builtins.filter (x: builtins.typeOf x == "string") (builtins.split sep s);

  matchLineFromFile =
    f: pattern:
    let
      matches = builtins.filter (x: (builtins.isString x) && ((builtins.match pattern x) != null)) (
        builtins.split "\n" (builtins.readFile f)
      );
    in
    if builtins.length matches == 0 then "" else builtins.elemAt matches 0;

  matchLine =
    pattern:
    matchLineFromFile "${flutterPkg}/engine/src/flutter/tools/android_sdk/packages.txt" pattern;

  cmdLineTools = builtins.replaceStrings [ "cmdline-tools" ";" ":" ] [ "" "" "" ] (
    matchLine "cmdline-tools;.*"
  );
  ndkVersions = splitString "," (
    builtins.replaceStrings [ "ndk" ";" ":" ] [ "" "" "" ] (matchLine "ndk;.*")
  );
  buildTools = splitString "," (
    builtins.replaceStrings [ "build-tools" ";" ":" ] [ "" "" "" ] (matchLine "build-tools;.*")
  );
  platforms = splitString "," (
    builtins.replaceStrings [ "platforms" ";" ":" "android-" ] [ "" "" "" "" ] (
      matchLine "platforms;.*"
    )
  );
in
pkgs.androidenv.composeAndroidPackages {
  cmdLineToolsVersion = cmdLineTools;
  toolsVersion = "latest";
  platformToolsVersion = "latest";
  buildToolsVersions = buildTools;
  includeEmulator = false;
  emulatorVersion = "latest";
  minPlatformVersion = null;
  maxPlatformVersion = "latest";
  platformVersions = platforms;

  includeSources = false;
  includeSystemImages = false;
  systemImageTypes = [ ];
  abiVersions = [
    "arm64-v8a"
  ];
  includeNDK = true;
  ndkVersions = ndkVersions;
  useGoogleAPIs = false;
  useGoogleTVAddOns = false;
  includeExtras = [ ];
  extraLicenses = [ ];
}
