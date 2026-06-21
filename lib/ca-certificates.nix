{ lib, pkgs }:
let
  bundleTarget = "/etc/ssl/certs/ca-certificates.crt";
in
{
  inherit bundleTarget;

  mkRoot =
    package:
    pkgs.runCommand "devcontainer-ca-certificates-root" { } ''
      set -euo pipefail

      ca_root=${lib.escapeShellArg "${package}"}
      out_bundle="$out${bundleTarget}"
      mkdir -p "$(dirname "$out_bundle")"

      resolve_bundle() {
        local path="$1"
        local target
        local rooted

        if [ -f "$path" ]; then
          printf '%s\n' "$path"
          return 0
        fi

        if [ -L "$path" ]; then
          target="$(readlink "$path")"
          case "$target" in
            /*)
              if [ -f "$target" ]; then
                printf '%s\n' "$target"
                return 0
              fi

              rooted="$ca_root$target"
              ;;
            *)
              rooted="$(dirname "$path")/$target"
              ;;
          esac

          if [ -f "$rooted" ]; then
            printf '%s\n' "$rooted"
            return 0
          fi
        fi

        return 1
      }

      bundle=""
      for candidate in \
        "$ca_root/etc/ssl/certs/ca-certificates.crt" \
        "$ca_root/etc/ssl/certs/ca-bundle.crt" \
        "$ca_root/etc/pki/tls/certs/ca-bundle.crt" \
        "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" \
        "${pkgs.cacert}/etc/ssl/certs/ca-certificates.crt"
      do
        if bundle="$(resolve_bundle "$candidate")"; then
          break
        fi
      done

      if [ -z "$bundle" ]; then
        echo "could not locate a CA certificate bundle in $ca_root" >&2
        exit 1
      fi

      cp -L "$bundle" "$out_bundle"
    '';
}
