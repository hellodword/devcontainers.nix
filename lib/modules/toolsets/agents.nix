{
  pkgs,
  ...
}:
let
  codex = pkgs.codex;
in
{
  config.devcontainer.profiles."toolset/agents" = {
    kind = "toolset";
    group = "13-agent-tools";
    packages = [ codex ];
    priority = 74;
    stability = "medium";
    sharing = "global";
    securityClass = "networked";
    provides.commands = [ "codex" ];
    tests.smoke = [
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
