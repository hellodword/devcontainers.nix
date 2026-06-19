{ ... }:
{
  config.devcontainer.metadata.snippets = [
    {
      privileged = false;
      capAdd = [ ];
      securityOpt = [ "label=disable" ];
    }
  ];
}
