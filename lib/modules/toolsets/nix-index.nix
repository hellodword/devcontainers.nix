{
  lib,
  config,
  system,
  inputs,
  ...
}:
let
  nixIndexPackages = inputs.nix-index-database.packages.${system};
  nixIndex = nixIndexPackages.nix-index-with-db;
  comma =
    if builtins.hasAttr "comma-with-db" nixIndexPackages then nixIndexPackages.comma-with-db else null;
  packages = [
    nixIndex
  ]
  ++ lib.optional (config.devcontainer.toolsets.nixIndex.comma.enable && comma != null) comma;
in
{
  config = lib.mkIf config.devcontainer.toolsets.nixIndex.enable {
    devcontainer.packages = packages;

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
