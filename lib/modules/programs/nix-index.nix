{ lib, config, ... }:
let
  cfg = config.programs.nix-index;
  packages = [
    cfg.package
  ]
  ++ lib.optional (cfg.comma.enable && cfg.comma.package != null) cfg.comma.package;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = packages;

    devcontainer.graph.nodes."toolset/nix-index" = {
      kind = "toolset";
      group = "12-nix-index-tools";
      paths = packages;
      stability = "stable";
      sharing = "global";
      priority = 89;
      securityClass = "trusted";
    };

    devcontainer.tests.smoke = [
      {
        name = "nix-index-tools";
        command = [
          "bash"
          "-lc"
          "command -v nix-index && command -v nix-locate"
        ];
      }
    ];
  };
}
