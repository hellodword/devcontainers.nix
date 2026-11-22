#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: nix-cache.sh print [--public-only | --ci]
       nix-cache.sh install [--system] [--public-only]

print emits the declared devcontainers.nix caches as nix.conf settings.
install writes devcontainers-nix-cache.conf and includes it from nix.conf.
--system installs into NIX_CONF_DIR (default /etc/nix); run as root for a daemon.
--public-only omits the host's local OCI proxy. --ci selects CI's loopback proxy.
EOF
}

operation=""
scope="local"
system=false

while (($# > 0)); do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  print | install)
    if [[ -n $operation ]]; then
      usage >&2
      exit 2
    fi
    operation="$1"
    shift
    ;;
  --public-only)
    scope="public"
    shift
    ;;
  --ci)
    scope="ci"
    shift
    ;;
  --system)
    system=true
    shift
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
done

if [[ -z $operation || ($operation == print && $system == true) || ($operation == install && $scope == ci) ]]; then
  usage >&2
  exit 2
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fragment_name="devcontainers-nix-cache.conf"

render() {
  nix --extra-experimental-features "nix-command flakes" eval --no-update-lock-file --raw \
    "${repo_root}#lib.x86_64-linux.cache.${scope}.text"
}

if [[ $operation == print ]]; then
  render
  exit 0
fi

if [[ $system == true ]]; then
  config_dir="${NIX_CONF_DIR:-/etc/nix}"
else
  config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/nix"
fi

mkdir -p -- "$config_dir"
temporary="$(mktemp "$config_dir/.${fragment_name}.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
render >"$temporary"
chmod 0644 "$temporary"
mv -- "$temporary" "$config_dir/$fragment_name"

include_line="include $fragment_name"
if ! grep -Fxq -- "$include_line" "$config_dir/nix.conf" 2>/dev/null; then
  printf '\n%s\n' "$include_line" >>"$config_dir/nix.conf"
fi
printf 'Installed cache settings in %s/nix.conf\n' "$config_dir" >&2
if [[ $system == true ]]; then
  printf 'Restart an active nix-daemon to load its updated trust settings.\n' >&2
fi
