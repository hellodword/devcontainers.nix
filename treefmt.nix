{ ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;
  programs.ruff-format.enable = true;
  programs.shfmt = {
    enable = true;
    indent_size = 2;
  };

  programs.prettier = {
    enable = true;
    includes = [
      "*.json"
      "*.jsonc"
      "*.md"
      "*.markdown"
      "*.yml"
      "*.yaml"
      "*.js"
      "*.cjs"
      "*.mjs"
      "*.ts"
      "*.cts"
      "*.mts"
      "*.jsx"
      "*.tsx"
      "*.vue"
      "*.html"
      "*.htm"
      "*.css"
      "*.scss"
    ];
  };

  settings.global.excludes = [
    "tests/ci/**"
    "tests/smoke/**"
    "tests/e2e/**"
    ".github/**"
    "README.md"
    "docs/**"
  ];
}
