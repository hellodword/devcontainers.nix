{ config, ... }:
let
  user = config.devcontainer.user;
in
{
  config.devcontainer = {
    user = {
      remoteUser = user.name;
      containerUser = user.name;
    };

    env.container = {
      HOME = user.home;
      USER = user.name;
      LOGNAME = user.name;
      SHELL = user.shell;
    };
    env.origins.container = {
      HOME = [ "core.user" ];
      USER = [ "core.user" ];
      LOGNAME = [ "core.user" ];
      SHELL = [ "core.user" ];
    };
  };
}
