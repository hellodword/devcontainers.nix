{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  moduleTypes = import ../types.nix { inherit lib; };
  inherit (moduleTypes) nonEmptyStringType;
  nonEmptyStringListType = types.nonEmptyListOf nonEmptyStringType;
  knownHostType = types.submodule (
    { name, ... }:
    {
      options = {
        hostNames = mkOption {
          type = nonEmptyStringListType;
          default = [ name ];
        };
        publicKey = mkOption { type = nonEmptyStringType; };
        certAuthority = mkOption {
          type = types.bool;
          default = false;
        };
      };
    }
  );
  cfg = config.programs.ssh;
  knownHostEntries = lib.mapAttrsToList (
    name: host:
    let
      marker = lib.optionalString host.certAuthority "@cert-authority ";
      hosts = lib.concatStringsSep "," host.hostNames;
    in
    "${marker}${hosts} ${host.publicKey}"
  ) cfg.knownHosts;
  knownHostsText = lib.concatStringsSep "\n" (knownHostEntries ++ [ "" ]);
  globalKnownHostsFiles = [
    "/etc/ssh/ssh_known_hosts"
  ]
  ++ map toString cfg.knownHostsFiles;
  algorithmLine =
    name: values: lib.optionalString (values != [ ]) "  ${name} ${lib.concatStringsSep "," values}\n";
  sshConfigText = ''
    Host *
      GlobalKnownHostsFile ${lib.concatStringsSep " " globalKnownHostsFiles}
  ''
  + lib.optionalString cfg.forwardX11 "  ForwardX11 yes\n"
  + algorithmLine "KexAlgorithms" cfg.algorithms.kexAlgorithms
  + algorithmLine "HostKeyAlgorithms" cfg.algorithms.hostKeyAlgorithms
  + algorithmLine "Ciphers" cfg.algorithms.ciphers
  + algorithmLine "MACs" cfg.algorithms.macs
  + cfg.extraConfig
  + "\n";
in
{
  options.programs.ssh = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    package = mkOption {
      type = types.package;
      default = pkgs.openssh;
    };
    knownHosts = mkOption {
      type = types.attrsOf knownHostType;
      default = { };
    };
    knownHostsFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
    };
    extraConfig = mkOption {
      type = types.lines;
      default = "";
    };
    algorithms = {
      kexAlgorithms = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      hostKeyAlgorithms = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      ciphers = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      macs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
    forwardX11 = mkOption {
      type = types.bool;
      default = false;
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."ssh/ssh_config".text = sshConfigText;
    environment.etc."ssh/ssh_known_hosts".text = knownHostsText;
  };
}
