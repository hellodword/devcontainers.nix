{
  pkgs,
  ...
}:
let
  codex = pkgs.agents-misc.codex;
in
{
  config.devcontainer.layers.bucketDefinitions."13-agent-tools" = {
    order = 15;
    owner = "toolsets/agents";
    purpose = "Agent command-line tooling.";
  };

  config.devcontainer.profiles."toolset/agents" = {
    kind = "toolset";
    group = "13-agent-tools";
    packages = [ codex ];
    priority = 74;
    stability = "medium";
    sharing = "global";
    securityClass = "networked";
    provides.commands = [ "codex" ];
    tests.cases."codex.cli" = {
      tags = [
        "smoke"
        "tooling"
        "codex"
      ];
      command = [
        "codex"
        "--version"
      ];
    };
  };
}
