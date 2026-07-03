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
    node-gyp
    vue-language-server
  ];
in
{
  config.devcontainer.layers.bucketDefinitions = {
    "nodejs-language" = {
      order = 22100;
      owner = "languages/nodejs";
      purpose = "Node.js language tooling, package manager helpers, and TypeScript support.";
    };
    "vscode-extensions-nodejs" = {
      order = 63000;
      owner = "languages/nodejs";
      purpose = "Node.js and web framework VS Code extensions.";
    };
  };

  config.devcontainer.profiles."language/nodejs" = {
    kind = "language";
    group = "nodejs-language";
    packages = [ ];
    priority = 72;
    stability = "medium";
    sharing = "image-family";
    securityClass = "trusted";
    composition.role = "bundle";
    includes = [
      "language/nodejs/core"
      "editor/prettier"
      "language/nodejs/smoke"
    ];
  };

  config.devcontainer.profiles."language/nodejs/core" = {
    kind = "language";
    group = "nodejs-language";
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
      "node-gyp"
      "vue-language-server"
    ];
    vscode = {
      extensions = {
        "dbaeumer.vscode-eslint" = {
          native = false;
          bucket = "vscode-extensions-nodejs";
          companionTools = [
            "node"
            "eslint"
          ];
        };
        "vue.volar" = {
          native = false;
          bucket = "vscode-extensions-nodejs";
          companionTools = [
            "node"
            "typescript-language-server"
            "vue-language-server"
          ];
        };
      };
      settings = {
        "typescript.tsdk" = "/usr/lib/node_modules/typescript/lib";
        "eslint.runtime" = "/usr/bin/node";
        "vue.server.path" = "/usr/bin/vue-language-server";
      };
    };
  };

  config.devcontainer.profiles."language/nodejs/smoke" = {
    kind = "language";
    group = "nodejs-language";
    packages = [ ];
    priority = 72;
    stability = "medium";
    sharing = "image-family";
    securityClass = "trusted";
    tests.cases."language.nodejs" = {
      tags = [
        "smoke"
        "language"
        "nodejs"
        "node"
      ];
      scripts = [
        {
          shell = "bash";
          interactive = false;
          command = ''
            set -e
            node --version
            npm --version
            npx --version
            pnpm --version
            yarn --version
            corepack --version
            node-gyp --version
            python --version
            cc --version
          '';
        }
      ];
    };
  };
}
