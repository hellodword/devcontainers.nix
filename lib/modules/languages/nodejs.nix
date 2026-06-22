{
  pkgs,
  ...
}:
let
  packages = with pkgs; [
    pnpm
    yarn
    typescript
    typescript-language-server
    eslint
    prettier
    node-gyp
  ];
in
{
  config.devcontainer.profiles."language/nodejs" = {
    kind = "language";
    group = "41-nodejs-language";
    packages = packages;
    priority = 72;
    stability = "medium";
    sharing = "image-family";
    securityClass = "trusted";
    provides.commands = [
      "pnpm"
      "yarn"
      "tsc"
      "typescript-language-server"
      "eslint"
      "prettier"
      "node-gyp"
    ];
    vscode = {
      extensions = {
        "dbaeumer.vscode-eslint" = {
          native = false;
          bucket = "83-vscode-extensions-nodejs";
          companionTools = [
            "node"
            "eslint"
          ];
        };
        "esbenp.prettier-vscode" = {
          native = false;
          bucket = "80-vscode-extensions-base";
          companionTools = [
            "node"
            "prettier"
          ];
        };
        "vue.volar" = {
          native = false;
          bucket = "83-vscode-extensions-nodejs";
          companionTools = [
            "node"
            "typescript-language-server"
          ];
        };
      };
      settings = {
        "typescript.tsdk" = "/usr/lib/node_modules/typescript/lib";
        "[javascript]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[typescript]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "eslint.runtime" = "/usr/bin/node";
      };
    };
    tests.capabilities = [ "language.nodejs" ];
  };
}
