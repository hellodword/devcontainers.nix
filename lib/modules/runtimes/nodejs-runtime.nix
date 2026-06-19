{ lib, pkgs, config, ... }:
let
  packages = [ pkgs.nodejs_22 ];
in
{
  config = lib.mkIf config.devcontainer.runtimes.nodejs.enable {
    devcontainer.packages = packages;
    devcontainer.env.container = {
      NODE_ENV = "development";
      NPM_CONFIG_CACHE = "$XDG_CACHE_HOME/npm";
      COREPACK_HOME = "$XDG_CACHE_HOME/corepack";
      PNPM_HOME = "$XDG_DATA_HOME/pnpm";
      YARN_CACHE_FOLDER = "$XDG_CACHE_HOME/yarn";
      NODE_REPL_HISTORY = "$XDG_STATE_HOME/node_repl_history";
    };
    devcontainer.path.segments.language = [ "$PNPM_HOME" ];
    devcontainer.graph.nodes."runtime/nodejs" = {
      kind = "runtime";
      group = "40-nodejs-runtime";
      paths = packages;
      stability = "stable";
      sharing = "cross-language";
      priority = 85;
      securityClass = "trusted";
    };
  };
}
