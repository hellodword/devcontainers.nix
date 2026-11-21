# Node.js runtime, package managers, TypeScript/Vue/Tailwind/CSS language tooling, and NODE environment.
{ pkgs }:
let
  nodePkg = pkgs.nodejs_latest or pkgs.nodejs;
  corepackCli = pkgs.runCommand "corepack-cli" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.corepack}/bin/corepack "$out/bin/corepack"
  '';
  usrPackages = [
    nodePkg
    corepackCli
    pkgs.pnpm
    pkgs.yarn
    pkgs.typescript
    pkgs.typescript-language-server
    pkgs.eslint
    pkgs.node-gyp
    pkgs.vue-language-server
    pkgs.tailwindcss-language-server
    pkgs.stylelint
  ];
in
{
  inherit usrPackages;
  typescriptPkg = pkgs.typescript;
  storeDeps = [
    nodePkg
    pkgs.corepack
    corepackCli
    pkgs.pnpm
    pkgs.yarn
    pkgs.typescript
    pkgs.typescript-language-server
    pkgs.eslint
    pkgs.node-gyp
    pkgs.vue-language-server
    pkgs.tailwindcss-language-server
    pkgs.stylelint
  ];
  pathSegments = [ "/home/vscode/.local/share/pnpm" ];
  env = {
    NODE_ENV = "development";
    NPM_CONFIG_CACHE = "/home/vscode/.cache/npm";
    COREPACK_HOME = "/home/vscode/.cache/corepack";
    PNPM_HOME = "/home/vscode/.local/share/pnpm";
    YARN_CACHE_FOLDER = "/home/vscode/.cache/yarn";
    NODE_REPL_HISTORY = "/home/vscode/.local/state/node_repl_history";
  };
}
