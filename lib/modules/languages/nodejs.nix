{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    pnpm
    yarn
    typescript
    eslint
    prettier
    node-gyp
  ];
in
{
  config = lib.mkIf config.devcontainer.languages.nodejs.enable {
    devcontainer.runtimes.nodejs.enable = true;
    environment.systemPackages = packages;
    devcontainer.vscode.extensions = [
      "dbaeumer.vscode-eslint"
      "esbenp.prettier-vscode"
      "vue.volar"
    ];
    devcontainer.vscode.settings = {
      "typescript.tsdk" = "/usr/local/share/typescript/lib";
      "[javascript]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[typescript]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "eslint.runtime" = "/usr/local/bin/node";
    };
    devcontainer.graph.nodes."language/nodejs" = {
      kind = "language";
      group = "41-nodejs-language";
      paths = packages;
      stability = "medium";
      sharing = "image-family";
      priority = 72;
      securityClass = "trusted";
    };
    devcontainer.tests.smoke = [
      {
        name = "node-version";
        command = [
          "node"
          "--version"
        ];
      }
      {
        name = "pnpm-version";
        command = [
          "pnpm"
          "--version"
        ];
      }
      {
        name = "node-package-managers";
        command = [
          "bash"
          "-lc"
          "npm --version && npx --version && corepack --version && yarn --version"
        ];
      }
      {
        name = "node-python-runtime";
        command = [
          "python"
          "--version"
        ];
      }
      {
        name = "node-c-env";
        command = [
          "cc"
          "--version"
        ];
      }
    ];
  };
}
