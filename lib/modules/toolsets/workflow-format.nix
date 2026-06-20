{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    just
    shellcheck
    shfmt
    editorconfig-core-c
  ];
in
{
  config = lib.mkIf config.devcontainer.toolsets.workflowFormat.enable {
    environment.systemPackages = packages;
    programs.direnv.enable = lib.mkDefault true;
    devcontainer.graph.nodes."toolset/workflow-format" = {
      kind = "toolset";
      group = "07-workflow-format-tools";
      paths = packages;
      stability = "stable";
      sharing = "global";
      priority = 82;
      securityClass = "trusted";
    };
  };
}
