# Agent CLI packages split into redistributable open-source and restricted unfree layers.
{ inputs, system }:
let
  codex = inputs.llm-agents.packages.${system}.codex;
  opencode = inputs.llm-agents.packages.${system}.opencode;
  antigravity-cli = inputs.llm-agents.packages.${system}.antigravity-cli;
in
{
  ossPackages = [
    codex
    opencode
  ];
  restrictedPackages = [
    antigravity-cli
  ];
  allPackages = [
    codex
    opencode
    antigravity-cli
  ];
}
