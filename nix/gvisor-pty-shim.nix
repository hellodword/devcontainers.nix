# Wrap pkgs.nix with libgvisor_pty_shim.so for single-user builds under runsc
# (google/gvisor#13738, fixed in google/gvisor#17244; retire at gvisor >= 20261130.0).
{ pkgs }:
pkgs.runCommandCC "devcontainer-nix-${pkgs.nix.version}"
  {
    nativeBuildInputs = [ pkgs.shellcheck ];
    meta = removeAttrs pkgs.nix.meta [ "outputsToInstall" ];
  }
  ''
    mkdir -p "$out/bin" "$out/libexec/devcontainer"
    shim="$out/libexec/devcontainer/libgvisor_pty_shim.so"

    "$CC" -shared -fPIC -O2 -Wall -Wextra -Werror \
      -DSHIM_SO_PATH="\"$shim\"" \
      -o "$shim" ${../runtime/gvisor-pty-shim/shim.c} -ldl

    cat > "$out/bin/nix" <<EOF
    #!${pkgs.bash}/bin/bash
    shim="$shim"
    LD_PRELOAD="\$shim\''${LD_PRELOAD:+:\$LD_PRELOAD}" exec -a "\$0" ${pkgs.nix}/bin/nix "\$@"
    EOF
    chmod 0755 "$out/bin/nix"
    shellcheck --shell=bash "$out/bin/nix"

    for tool in ${pkgs.nix}/bin/*; do
      name="$(basename "$tool")"
      if [ "$name" != "nix" ]; then
        ln -s nix "$out/bin/$name"
      fi
    done

    for sub in etc lib; do
      if [ -e "${pkgs.nix}/$sub" ]; then
        ln -s "${pkgs.nix}/$sub" "$out/$sub"
      fi
    done
    mkdir -p "$out/share"
    for item in ${pkgs.nix}/share/*; do
      ln -s "$item" "$out/share/$(basename "$item")"
    done
    if [ -d "${pkgs.nix.man or ""}/share/man" ]; then
      ln -s "${pkgs.nix.man}/share/man" "$out/share/man"
    fi
    for item in ${pkgs.nix}/libexec/*; do
      ln -s "$item" "$out/libexec/$(basename "$item")"
    done

    mkdir -p "$TMPDIR/home" "$TMPDIR/nix-state" "$TMPDIR/nix-log" "$TMPDIR/nix-conf"
    HOME="$TMPDIR/home" \
      NIX_STATE_DIR="$TMPDIR/nix-state" \
      NIX_LOG_DIR="$TMPDIR/nix-log" \
      NIX_CONF_DIR="$TMPDIR/nix-conf" \
      "$out/bin/nix" --version >/dev/null
    HOME="$TMPDIR/home" \
      NIX_STATE_DIR="$TMPDIR/nix-state" \
      NIX_LOG_DIR="$TMPDIR/nix-log" \
      NIX_CONF_DIR="$TMPDIR/nix-conf" \
      "$out/bin/nix-store" --version >/dev/null
    HOME="$TMPDIR/home" \
      NIX_STATE_DIR="$TMPDIR/nix-state" \
      NIX_LOG_DIR="$TMPDIR/nix-log" \
      NIX_CONF_DIR="$TMPDIR/nix-conf" \
      "$out/bin/nix-hash" --type sha256 --flat "$shim" >/dev/null
  ''
