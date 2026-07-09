{ ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;

  programs.prettier = {
    enable = true;
    includes = [
      "*.md"
      "*.markdown"
      "*.yaml"
      "*.yml"
    ];
  };

  settings = {
    excludes = [
      ".direnv/*"
      ".git/*"
      "result"
      "result-*"
      "node_modules/*"
      "vendor/*"
      ".work"
      "tmp"
      "flake.lock"
      "AGENTS.md"
      ".agents"
      ".vscode"
      ".devcontainer"
    ];
  };
}
