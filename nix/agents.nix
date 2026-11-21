# Agent CLI packages split into redistributable open-source and restricted unfree layers.
{ inputs, system }:
let
  codex = inputs.llm-agents.packages.${system}.codex;
  opencode = inputs.llm-agents.packages.${system}.opencode;
  vm-test-submit = inputs.agents-misc.packages.${system}.vm-test-submit;
  antigravity-cli = inputs.llm-agents.packages.${system}.antigravity-cli;
in
{
  ossPackages = [
    codex
    opencode
    vm-test-submit
  ];
  restrictedPackages = [
    antigravity-cli
  ];
  allPackages = [
    codex
    opencode
    vm-test-submit
    antigravity-cli
  ];
}
