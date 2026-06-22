{ lib, config, ... }:
let
  cfg = config.programs.nix-index;
  packages = [
    cfg.package
  ]
  ++ lib.optional (cfg.comma.enable && cfg.comma.package != null) cfg.comma.package;
in
{
  config = lib.mkMerge [
    {
      devcontainer.profiles."toolset/nix-index" = {
        kind = "toolset";
        group = "12-nix-index-tools";
        packages = packages;
        priority = 89;
        stability = "stable";
        sharing = "global";
        securityClass = "trusted";
        provides.commands = [
          "nix-index"
          "nix-locate"
          "comma"
        ];
        tests.capabilities = [ "nix-index.tools" ];
      };
    }

    (lib.mkIf config.devcontainer.profiles."toolset/nix-index".enable {
      programs.nix-index.enable = lib.mkDefault true;
      programs.nix-index.comma.enable = lib.mkDefault config.devcontainer.toolsets.nixIndex.comma.enable;
    })
  ];
}
