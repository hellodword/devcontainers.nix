{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.runtimes.nodejs;
  nodejs = if cfg.package == null then pkgs.nodejs else cfg.package;
  packages = [ nodejs ];
in
{
  config = lib.mkIf cfg.enable {
    devcontainer.packages = packages;
    devcontainer.env.container = {
      NODE_ENV = "development";
      NPM_CONFIG_CACHE = "$XDG_CACHE_HOME/npm";
      COREPACK_HOME = "$XDG_CACHE_HOME/corepack";
      PNPM_HOME = "$XDG_DATA_HOME/pnpm";
      YARN_CACHE_FOLDER = "$XDG_CACHE_HOME/yarn";
      NODE_REPL_HISTORY = "$XDG_STATE_HOME/node_repl_history";
    };
    devcontainer.env.origins.container = {
      NODE_ENV = [ "runtimes.nodejs" ];
      NPM_CONFIG_CACHE = [ "runtimes.nodejs" ];
      COREPACK_HOME = [ "runtimes.nodejs" ];
      PNPM_HOME = [ "runtimes.nodejs" ];
      YARN_CACHE_FOLDER = [ "runtimes.nodejs" ];
      NODE_REPL_HISTORY = [ "runtimes.nodejs" ];
    };
    devcontainer.path.segments.language = [ "$PNPM_HOME" ];
    devcontainer.path.segmentOrigins.language = {
      "$PNPM_HOME" = [ "runtimes.nodejs" ];
    };
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
