{
  inputs,
  system,
  ...
}:
let
  codex = inputs.llm-agents.packages.${system}.codex;
  opencode = inputs.llm-agents.packages.${system}.opencode;
  antigravity-cli = inputs.llm-agents.packages.${system}.antigravity-cli;
  vm-test-submit = inputs.agents-misc.packages.${system}.vm-test-submit;
in
{
  config.devcontainer.layers.bucketDefinitions."agent-tools" = {
    order = 11200;
    owner = "toolsets/agents";
    purpose = "Agent command-line tooling.";
  };

  config.devcontainer.profiles."toolset/agents" = {
    kind = "toolset";
    group = "agent-tools";
    packages = [
      codex
      opencode
      antigravity-cli
      vm-test-submit
    ];
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
      scripts = [
        {
          shell = "bash";
          interactive = false;
          command = "codex --version";
        }
      ];
    };
    tests.cases."opencode.cli" = {
      tags = [
        "smoke"
        "tooling"
        "opencode"
      ];
      scripts = [
        {
          shell = "bash";
          interactive = false;
          command = "opencode --version";
        }
      ];
    };
    tests.cases."antigravity-cli.cli" = {
      tags = [
        "smoke"
        "tooling"
        "antigravity-cli"
      ];
      scripts = [
        {
          shell = "bash";
          interactive = false;
          command = "agy --version";
        }
      ];
    };
    tests.cases."vm-test-submit.cli" = {
      tags = [
        "smoke"
        "tooling"
        "vm-test-submit"
      ];
      scripts = [
        {
          shell = "bash";
          interactive = false;
          command = "vm-test-submit --version";
        }
      ];
    };
  };
}
