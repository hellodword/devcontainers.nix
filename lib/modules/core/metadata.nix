{
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  options.devcontainer.metadata.snippets = mkOption {
    type = types.listOf types.attrs;
    default = [ ];
  };

  config.devcontainer.metadata.snippets = [
    {
      privileged = false;
      capAdd = [ ];
      securityOpt = [ "label=disable" ];
    }
  ];
}
