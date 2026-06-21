{
  lib,
  pkgs,
  config,
  ...
}:
let
  caCertificates = import ../../ca-certificates.nix { inherit lib pkgs; };
  cfg = config.security.pki;
  certBundleTarget = caCertificates.bundleTarget;
  baseBundleRoot = caCertificates.mkRoot cfg.package;
  baseBundle = "${baseBundleRoot}${certBundleTarget}";
  needsCustomBundle = cfg.certificates != [ ] || cfg.certificateFiles != [ ] || cfg.blacklist != [ ];
  extraCerts = pkgs.writeText "extra-ca-certificates.pem" (
    lib.concatStringsSep "\n" (cfg.certificates ++ [ "" ])
  );
  blacklist = pkgs.writeText "ca-certificate-blacklist.txt" (
    lib.concatStringsSep "\n" (cfg.blacklist ++ [ "" ])
  );
  appendCertificateFiles = lib.concatMapStringsSep "\n" (file: ''
    cat ${file} >>"$tmp"
    printf '\n' >>"$tmp"
  '') cfg.certificateFiles;
  customBundle = pkgs.runCommand "devcontainer-ca-certificates.crt" { } ''
    tmp="$out.tmp"
    cp ${baseBundle} "$tmp"
    cat ${extraCerts} >>"$tmp"
    ${appendCertificateFiles}
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      awk -v RS= -v ORS='\n\n' -v pattern="$pattern" 'index($0, pattern) == 0 { print }' "$tmp" >"$tmp.next"
      mv "$tmp.next" "$tmp"
    done <${blacklist}
    mv "$tmp" "$out"
  '';
  bundleSource = if needsCustomBundle then customBundle else baseBundle;
in
{
  config = lib.mkIf cfg.installCACerts {
    environment.etc."ssl/certs/ca-certificates.crt".source = bundleSource;
  };
}
