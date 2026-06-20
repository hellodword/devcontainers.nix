{ lib, config, ... }:
{
  config = lib.mkIf config.devcontainer.toolsets.nixIndex.enable {
    programs.nix-index.enable = lib.mkDefault true;
    programs.nix-index.comma.enable = lib.mkDefault config.devcontainer.toolsets.nixIndex.comma.enable;
  };
}
