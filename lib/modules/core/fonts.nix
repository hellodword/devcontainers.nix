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
        devcontainer.tests.capabilities = [
          "fontconfig.core"
          "fontconfig.cjk-emoji"
        ];
      })
    ]
  );
}
