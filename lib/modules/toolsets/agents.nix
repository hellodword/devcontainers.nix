{
  lib,
  pkgs,
  config,
  ...
}:
let
  codex = pkgs.codex;
in
{
  config = lib.mkIf config.devcontainer.toolsets.agents.enable {
    environment.systemPackages = [ codex ];

    devcontainer.graph.nodes."toolset/agents" = {
      kind = "toolset";
      group = "13-agent-tools";
      paths = [ codex ];
      stability = "medium";
      sharing = "global";
      priority = 74;
      securityClass = "networked";
    };

    devcontainer.tests.smoke = [
      {
        name = "codex-version";
        command = [
          "codex"
          "--version"
        ];
      }
    ];
  };
}
