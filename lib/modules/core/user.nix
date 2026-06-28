{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  user = config.devcontainer.user;
in
{
  options.devcontainer.user = {
    name = mkOption {
      type = types.enum [ "vscode" ];
      default = "vscode";
    };
    uid = mkOption {
      type = types.enum [ 1000 ];
      default = 1000;
    };
    group = mkOption {
      type = types.enum [ "vscode" ];
      default = "vscode";
    };
    gid = mkOption {
      type = types.enum [ 1000 ];
      default = 1000;
    };
    home = mkOption {
      type = types.enum [ "/home/vscode" ];
      default = "/home/vscode";
    };
    shell = mkOption {
      type = types.enum [ "/bin/bash" ];
      default = "/bin/bash";
    };
    remoteUser = mkOption {
      type = types.enum [ "vscode" ];
      default = "vscode";
    };
    containerUser = mkOption {
      type = types.enum [ "vscode" ];
      default = "vscode";
    };
    updateRemoteUserUID = mkOption {
      type = types.enum [ false ];
      default = false;
    };
  };

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
