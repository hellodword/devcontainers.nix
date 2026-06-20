{ config, ... }:
let
  user = config.devcontainer.user;
in
{
  config = {
    devcontainer.user = {
      remoteUser = user.name;
      containerUser = user.name;
    };

    environment.variables = {
      HOME = user.home;
      USER = user.name;
      LOGNAME = user.name;
      SHELL = user.shell;
    };
    environment.variableOrigins = {
      HOME = [ "core.user" ];
      USER = [ "core.user" ];
      LOGNAME = [ "core.user" ];
      SHELL = [ "core.user" ];
    };
  };
}
