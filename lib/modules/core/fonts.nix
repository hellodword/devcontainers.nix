{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  fontAliasType = types.submodule {
    options = {
      binding = mkOption {
        type = types.enum [
          "same"
          "weak"
          "strong"
        ];
        default = "same";
      };
      prefer = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      accept = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      default = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };
  cfg = config.devcontainer.fonts;
  fontconfig = cfg.fontconfig;
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
  fontPackages = cfg.packages ++ lib.optional fontconfig.enable fontconfig.package;
  toolSmokeCommand = lib.concatMapStringsSep " && " (
    tool: "command -v ${tool} >/dev/null"
  ) fontconfigTools;
in
{
  options.devcontainer.fonts = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };
    packages = mkOption {
      type = types.listOf types.package;
      default = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
        noto-fonts-color-emoji
      ];
    };
    fontconfig = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      package = mkOption {
        type = types.package;
        default = pkgs.fontconfig;
      };
      includeUserConf = mkOption {
        type = types.bool;
        default = true;
      };
      localConf = mkOption {
        type = types.lines;
        default = "";
      };
      defaultFonts = {
        sansSerif = mkOption {
          type = types.listOf types.str;
          default = [
            "Noto Sans CJK SC"
            "Noto Sans"
          ];
        };
        serif = mkOption {
          type = types.listOf types.str;
          default = [
            "Noto Serif CJK SC"
            "Noto Serif"
          ];
        };
        monospace = mkOption {
          type = types.listOf types.str;
          default = [
            "Noto Sans Mono CJK SC"
            "Noto Sans Mono"
          ];
        };
        emoji = mkOption {
          type = types.listOf types.str;
          default = [ "Noto Color Emoji" ];
        };
      };
      aliases = mkOption {
        type = types.attrsOf fontAliasType;
        default = { };
      };
    };
  };

  config = lib.mkMerge [
    {
      devcontainer.layers.bucketDefinitions."fonts-runtime" = {
        order = 200;
        owner = "core/fonts";
        purpose = "Default fonts, fontconfig tools, and font cache runtime support.";
      };
    }

    (lib.mkIf cfg.enable (
      lib.mkMerge [
        {
          environment.systemPackages = fontPackages;
        }

        (lib.mkIf (fontPackages != [ ]) {
          devcontainer.graph.nodes."runtime/fonts" = {
            kind = "runtime";
            group = "fonts-runtime";
            paths = fontPackages;
            stability = "very-stable";
            sharing = "global";
            priority = 97;
            securityClass = "trusted";
          };
        })

        (lib.mkIf fontconfig.enable {
          devcontainer.tests.cases = {
            "fontconfig.core" = {
              tags = [
                "smoke"
                "baseline"
                "e2e-baseline"
                "fontconfig"
              ];
              command = [
                "bash"
                "-lc"
                toolSmokeCommand
              ];
            };
            "fontconfig.cjk-emoji" = {
              tags = [
                "smoke"
                "baseline"
                "e2e-baseline"
                "fontconfig"
                "cjk"
                "emoji"
              ];
              command = [
                "bash"
                "-lc"
                "fc-match 'sans-serif:lang=zh-cn:charset=0x95e8' | grep -F 'Noto Sans CJK SC' >/dev/null && fc-match 'serif:lang=zh-cn:charset=0x95e8' | grep -F 'Noto Serif CJK SC' >/dev/null && fc-match 'monospace:lang=zh-cn:charset=0x95e8' | grep -F 'Noto Sans Mono CJK SC' >/dev/null && fc-match 'emoji:charset=0x1f600' | grep -F 'Noto Color Emoji' >/dev/null"
              ];
            };
          };
        })
      ]
    ))
  ];
}
