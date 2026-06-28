{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.programs.nix-index;
  packages = [
    cfg.package
  ]
  ++ lib.optional (cfg.comma.enable && cfg.comma.package != null) cfg.comma.package;
in
{
  options.devcontainer.toolsets.nixIndex.comma.enable = mkOption {
    type = types.bool;
    default = true;
  };

  config = lib.mkMerge [
    {
      devcontainer.layers.bucketDefinitions."nix-index-tools" = {
        order = 11100;
        owner = "toolsets/nix-index";
        purpose = "nix-index and comma command database tools.";
      };

      devcontainer.profiles."toolset/nix-index" = {
        kind = "toolset";
        group = "nix-index-tools";
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
        tests.cases."nix-index.tools" = {
          tags = [
            "smoke"
            "tooling"
            "nix-index"
          ];
          command = [
            "bash"
            "-lc"
            "command -v nix-index >/dev/null && command -v nix-locate >/dev/null"
          ];
        };
      };
    }

    (lib.mkIf config.devcontainer.profiles."toolset/nix-index".enable {
      programs.nix-index.enable = lib.mkDefault true;
      programs.nix-index.comma.enable = lib.mkDefault config.devcontainer.toolsets.nixIndex.comma.enable;
    })
  ];
}
