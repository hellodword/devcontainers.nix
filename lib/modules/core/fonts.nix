{
  lib,
  config,
  ...
}:
let
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
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = fontPackages;
      }

      (lib.mkIf (fontPackages != [ ]) {
        devcontainer.graph.nodes."runtime/fonts" = {
          kind = "runtime";
          group = "02-fonts-runtime";
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
  );
}
