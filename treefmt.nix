{ ... }:
{
  projectRootFile = "flake.nix";

  programs.nixfmt.enable = true;

  programs.prettier = {
    enable = true;
    includes = [
      "*.json"
      "*.jsonc"
      "*.md"
      "*.markdown"
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
}
