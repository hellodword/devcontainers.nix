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
    tailwindcss-language-server
    stylelint
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
      "tailwindcss-language-server"
      "stylelint"
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
        "bradlc.vscode-tailwindcss" = {
          native = false;
          bucket = "vscode-extensions-nodejs";
          companionTools = [
            "node"
            "tailwindcss-language-server"
          ];
        };
        "stylelint.vscode-stylelint" = {
          native = false;
          bucket = "vscode-extensions-nodejs";
          companionTools = [
            "node"
            "stylelint"
          ];
        };
        "yoavbls.pretty-ts-errors" = {
          native = false;
          bucket = "vscode-extensions-nodejs";
          companionTools = [ "typescript-language-server" ];
        };
      };
      settings = {
        "typescript.tsdk" = "/usr/lib/node_modules/typescript/lib";
        "eslint.workingDirectories" = [ { mode = "auto"; } ];
        "eslint.runtime" = "/usr/bin/node";
        "vue.server.path" = "/usr/bin/vue-language-server";
        "stylelint.runtime" = "/usr/bin/node";
        "stylelint.stylelintPath" = "/usr/lib/node_modules/stylelint";
        "stylelint.validate" = [
          "css"
          "scss"
          "less"
          "postcss"
          "vue"
        ];
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
            # tailwindcss-language-server --help >/dev/null
            stylelint --version
            python --version
            cc --version
          '';
        }
      ];
    };
  };
}
