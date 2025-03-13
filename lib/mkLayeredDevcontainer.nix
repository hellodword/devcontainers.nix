{
  pkgs,
  name,
  tag ? "latest",
  packages ? [ ],
  extensions ? [ ],
  envVars ? { },
}:
let
  lib = pkgs.lib;
  username = "vscode";
  extensionsJson = map (x: {
    identifier.id = x.vscodeExtUniqueId;
    version = x.version;
    location = {
      "$mid" = 1;
      scheme = "file";
      path = "${x}/share/vscode/extensions/${x.vscodeExtUniqueId}";
    };
  }) extensions;
  extensionsDirs = [
    # VSCode
    ".vscode-server"
    # codespaces
    ".vscode-remote"
  ];
  profile = pkgs.writeShellScript "profile" ''
    if [ -d /etc/profile.d ]; then
      for i in /etc/profile.d/*.sh; do
        if [ -r $i ]; then
          . $i
        fi
      done
      unset i
    fi
  '';
  extProfile = pkgs.writeShellScript "ext-profile" ''
    if [ -f $HOME/.ext-profile ]; then
      exit 0
    fi
    touch $HOME/.ext-profile

    ${builtins.concatStringsSep "\n" (
      map (extensionsDir: ''
        if [ ! -f $HOME/${extensionsDir}/extensions/extensions.json ]; then
          mkdir -p $HOME/${extensionsDir}/extensions
          echo '[]' > $HOME/${extensionsDir}/extensions/extensions.json

        fi
        cat > /tmp/extensions.json <<EOF
        ${builtins.toJSON extensionsJson}
        EOF
        ALL="$(jq -s '.[0] + .[1]' /tmp/extensions.json $HOME/${extensionsDir}/extensions/extensions.json)"
        echo "$ALL" > $HOME/${extensionsDir}/extensions/extensions.json
      '') extensionsDirs
    )}

    chown -R ${username}:${username} $HOME
  '';
  envVarsFull =
    {
      # required by vscode terminal, but allow overriding
      SHELL = "/bin/bash";
    }
    // envVars
    // {
      # required by vscode-server and its node
      LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib${
        if builtins.hasAttr "LD_LIBRARY_PATH" envVars then ":${envVars.LD_LIBRARY_PATH}" else ""
      }";
    };
in
pkgs.dockerTools.streamLayeredImage {
  maxLayers = 125;
  inherit name tag;
  config = {
    User = "${username}:${username}";
    Env = map (x: "${x}=${envVarsFull."${x}"}") (builtins.attrNames envVarsFull);
  };
  contents = lib.lists.unique (
    (with pkgs.dockerTools; [
      usrBinEnv
      binSh
      caCertificates
    ])
    ++ (with pkgs; [
      bash
      coreutils
      gnutar
      gzip
      gnused
      gnugrep

      jq
    ])
    ++ packages
  );

  extraCommands = ''
    mkdir -m 1777 tmp

    mkdir -p etc/profile.d
    ln -s ${profile} etc/profile
    ln -s ${extProfile} etc/profile.d/11-ext-profile.sh

    # https://github.com/manesiotise/plutus-apps/blob/dbafa0ffdc1babcf8e9143ca5a7adde78d021a9a/nix/devcontainer-docker-image.nix#L99-L103
    # allow ubuntu ELF binaries to run. VSCode copies it's own.
    mkdir -p lib64
    chmod +w lib64
    ln -s ${pkgs.glibc}/lib64/ld-linux-x86-64.so.2 lib64/ld-linux-x86-64.so.2
    ln -s ${pkgs.gcc-unwrapped.lib}/lib64/libstdc++.so.6 lib64/libstdc++.so.6
    chmod -w lib64
  '';

  # https://github.com/devcontainers/features/blob/main/src/common-utils/main.sh
  fakeRootCommands = ''
    #!${pkgs.runtimeShell}
    set -eux

    ${pkgs.dockerTools.shadowSetup}

    chmod 0777 tmp

    groupadd --system --gid 1000 ${username}
    useradd -s /bin/bash --system --uid 1000 --gid ${username} -m ${username}

    mkdir -p /workspaces
    chown ${username}:${username} /workspaces
  '';
  enableFakechroot = true;
}
