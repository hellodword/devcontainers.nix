{ pkgs, lib }:
{ config }:
let
  cfg = config.devcontainer.fonts;
  fontconfig = cfg.fontconfig;
  fontconfigPackage = fontconfig.package;
  fontconfigOut = lib.getOutput "out" fontconfigPackage;
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  packageName = drv: drv.pname or drv.name or (builtins.baseNameOf (pathString drv));
  fontconfigTools = [
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
  xmlFamily = family: "<family>${lib.escapeXML family}</family>";
  fontBlock =
    key: fonts:
    lib.optionalString (fonts != [ ]) ''
      <${key}>
        ${lib.concatMapStringsSep "\n    " xmlFamily fonts}
      </${key}>
    '';
  defaultFontAlias =
    generic: fonts:
    lib.optionalString (fonts != [ ]) ''
      <alias binding="same">
        <family>${lib.escapeXML generic}</family>
        <prefer>
          ${lib.concatMapStringsSep "\n      " xmlFamily fonts}
        </prefer>
      </alias>
    '';
  defaultFontsConf = pkgs.writeText "fc-52-devcontainer-default-fonts.conf" ''
    <?xml version='1.0'?>
    <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
    <fontconfig>
      <!-- Default fonts -->
      ${defaultFontAlias "sans-serif" fontconfig.defaultFonts.sansSerif}
      ${defaultFontAlias "serif" fontconfig.defaultFonts.serif}
      ${defaultFontAlias "monospace" fontconfig.defaultFonts.monospace}
      ${defaultFontAlias "emoji" fontconfig.defaultFonts.emoji}
    </fontconfig>
  '';
  aliasBlock = family: opts: ''
    <alias binding="${opts.binding}">
      <family>${lib.escapeXML family}</family>
      ${fontBlock "prefer" opts.prefer}
      ${fontBlock "accept" opts.accept}
      ${fontBlock "default" opts.default}
    </alias>
  '';
  aliasesConf = pkgs.writeText "fc-53-devcontainer-aliases.conf" ''
    <?xml version='1.0'?>
    <!DOCTYPE fontconfig SYSTEM 'urn:fontconfig:fonts.dtd'>
    <fontconfig>
      <!-- User defined aliases -->
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList aliasBlock fontconfig.aliases)}
    </fontconfig>
  '';
  localConfFile = pkgs.writeText "fc-51-devcontainer-local.conf" fontconfig.localConf;
  fontsConf = pkgs.makeFontsConf {
    fontconfig = fontconfigPackage;
    fontDirectories = cfg.packages;
    includes = [ "/etc/fonts/conf.d" ];
  };
  root =
    if cfg.enable && fontconfig.enable then
      pkgs.runCommand "${config.devcontainer.image.name}-fonts" { } ''
        mkdir -p "$out/etc/fonts/conf.d"
        ln -s ${fontsConf} "$out/etc/fonts/fonts.conf"

        for conf in ${fontconfigOut}/etc/fonts/conf.d/*; do
          name="$(basename "$conf")"
          ${lib.optionalString (!fontconfig.includeUserConf) ''
            if [ "$name" = "50-user.conf" ]; then
              continue
            fi
          ''}
          ln -s "$conf" "$out/etc/fonts/conf.d/$name"
        done

        ${lib.optionalString (fontconfig.localConf != "") ''
          ln -s ${localConfFile} "$out/etc/fonts/local.conf"
        ''}
        ln -s ${defaultFontsConf} "$out/etc/fonts/conf.d/52-devcontainer-default-fonts.conf"
        ln -s ${aliasesConf} "$out/etc/fonts/conf.d/53-devcontainer-aliases.conf"
      ''
    else
      pkgs.runCommand "${config.devcontainer.image.name}-fonts-disabled" { } ''
        mkdir -p "$out"
      '';
in
{
  inherit root;
  report = {
    enabled = cfg.enable;
    packages = map (package: {
      name = packageName package;
      path = pathString package;
    }) cfg.packages;
    fontconfig = {
      enabled = cfg.enable && fontconfig.enable;
      package = packageName fontconfigPackage;
      packagePath = pathString fontconfigPackage;
      configPackagePath = pathString fontconfigOut;
      configPath = "/etc/fonts/fonts.conf";
      confDir = "/etc/fonts/conf.d";
      includeUserConf = fontconfig.includeUserConf;
      localConf = {
        enabled = fontconfig.localConf != "";
        path = "/etc/fonts/local.conf";
      };
      defaultFonts = fontconfig.defaultFonts;
      aliases = fontconfig.aliases;
      tools = fontconfigTools;
      globalFontconfigFile = null;
      cache = {
        preGenerated = false;
        systemCacheDir = "/var/cache/fontconfig";
        userCache = "$XDG_CACHE_HOME/fontconfig";
      };
    };
  };
}
