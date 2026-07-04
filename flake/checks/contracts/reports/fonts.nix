{
  lib,
  images,
  contractLib,
  ...
}:

let
  requiredFontPackages = [
    "noto-fonts"
    "noto-fonts-cjk-sans"
    "noto-fonts-cjk-serif"
    "noto-fonts-color-emoji"
  ];
  requiredFontconfigTools = [
    "fc-cache"
    "fc-list"
    "fc-match"
    "fc-query"
    "fc-scan"
    "fc-validate"
    "fc-cat"
    "fc-conflist"
    "fc-pattern"
  ];
  perImage = lib.mapAttrsToList (
    name: image:
    let
      report = image.fonts.report;
      fontconfig = report.fontconfig or { };
      packageNames = map (entry: entry.name) (report.packages or [ ]);
      missingPackages = builtins.filter (
        package: !(builtins.elem package packageNames)
      ) requiredFontPackages;
      checks = {
        fontsEnabled = report.enabled or false;
        fontconfigEnabled = fontconfig.enabled or false;
        packageName = (fontconfig.package or null) == "fontconfig";
        configPath = (fontconfig.configPath or null) == "/etc/fonts/fonts.conf";
        confDir = (fontconfig.confDir or null) == "/etc/fonts/conf.d";
        requiredPackages = missingPackages == [ ];
        tools = contractLib.sameSet (fontconfig.tools or [ ]) requiredFontconfigTools;
        defaultSansSerif =
          (fontconfig.defaultFonts.sansSerif or [ ]) == [
            "Noto Sans CJK SC"
            "Noto Sans"
          ];
        defaultSerif =
          (fontconfig.defaultFonts.serif or [ ]) == [
            "Noto Serif CJK SC"
            "Noto Serif"
          ];
        defaultMonospace =
          (fontconfig.defaultFonts.monospace or [ ]) == [
            "Noto Sans Mono CJK SC"
            "Noto Sans Mono"
          ];
        defaultEmoji = (fontconfig.defaultFonts.emoji or [ ]) == [ "Noto Color Emoji" ];
        aliasesEmpty = (fontconfig.aliases or { }) == { };
        includeUserConf = fontconfig.includeUserConf or false;
        noGlobalFontconfigFile = (fontconfig.globalFontconfigFile or null) == null;
        cacheNotPregenerated = ((fontconfig.cache or { }).preGenerated or true) == false;
      };
    in
    {
      inherit name checks;
      details = {
        inherit missingPackages;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-fonts = contractLib.mkAssertedJsonCheck "contracts-reports-fonts" [ allValid ] {
    images = perImage;
  };
}
