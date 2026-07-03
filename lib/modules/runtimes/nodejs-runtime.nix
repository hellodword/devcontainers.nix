{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.devcontainer.runtimes.nodejs;
  nodejs = if cfg.package == null then pkgs.nodejs else cfg.package;
  corepackCommand = pkgs.runCommand "corepack-command" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.corepack}/bin/corepack "$out/bin/corepack"
  '';
  packages = [
    nodejs
    corepackCommand
  ];
in
{
  options.devcontainer.runtimes.nodejs.package = mkOption {
    type = types.nullOr types.package;
    default = null;
  };

  config.devcontainer = {
    layers.bucketDefinitions."nodejs-runtime" = {
      order = 22000;
      owner = "runtimes/nodejs-runtime";
      purpose = "Node.js runtime, npm, npx, and corepack.";
    };

    profiles."runtime/nodejs" = {
      kind = "runtime";
      group = "nodejs-runtime";
      packages = packages;
      priority = 85;
      stability = "stable";
      sharing = "cross-language";
      securityClass = "trusted";
      provides.commands = [
        "node"
        "npm"
        "npx"
        "corepack"
      ];
      env = {
        variables = {
          NODE_ENV = "development";
          NPM_CONFIG_CACHE = "$XDG_CACHE_HOME/npm";
          COREPACK_HOME = "$XDG_CACHE_HOME/corepack";
          PNPM_HOME = "$XDG_DATA_HOME/pnpm";
          YARN_CACHE_FOLDER = "$XDG_CACHE_HOME/yarn";
          NODE_REPL_HISTORY = "$XDG_STATE_HOME/node_repl_history";
        };
        path = [ "$PNPM_HOME" ];
      };
      tests.cases."runtime.nodejs" = {
        tags = [
          "smoke"
          "runtime"
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
              corepack --version
            '';
          }
        ];
      };
    };
  };
}
