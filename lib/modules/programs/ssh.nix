{ lib, config, ... }:
let
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
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    environment.etc."ssh/ssh_config".text = sshConfigText;
    environment.etc."ssh/ssh_known_hosts".text = knownHostsText;

    devcontainer.tests.smoke = [
      {
        name = "ssh-global-config";
        command = [
          "bash"
          "-lc"
          "test -r /etc/ssh/ssh_config && ssh -G example.com >/dev/null"
        ];
      }
    ];
  };
}
