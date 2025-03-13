# https://github.com/niksi-aalto/niksi-devcontainer

{
  pkgs,
  name,
  tag ? "latest",
  fromImage,
  paths ? [ ],
  extensions ? [ ],
  pathsToLink ? [
    "/bin"
    "/usr"
  ],
  envVars ? { },
}:
let
  lib = pkgs.lib;
  username = "vscode";
  envProfile = pkgs.writeText "env-profile" ''
    ${builtins.concatStringsSep "\n" (
      map (x: "export ${x}=${envVars."${x}"}") (builtins.attrNames envVars)
    )}
  '';
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
  extProfile = pkgs.writeText "ext-profile" ''
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
        ALL="$(${lib.getExe pkgs.jq} -s '.[0] + .[1]' /tmp/extensions.json $HOME/${extensionsDir}/extensions/extensions.json)"
        echo "$ALL" > $HOME/${extensionsDir}/extensions/extensions.json
      '') extensionsDirs
    )}

    chown -R ${username}:${username} $HOME
  '';
in
pkgs.dockerTools.buildImage {
  inherit name tag fromImage;
  diskSize = 1024 * 2;
  copyToRoot = pkgs.buildEnv {
    name = "env";
    paths = lib.lists.unique (
      paths
      ++ [ pkgs.dockerTools.binSh ]
      ++ [
        (pkgs.runCommand "profile" { } ''
          mkdir -p $out/etc/profile.d
          cp ${envProfile} $out/etc/profile.d/10-env-profile.sh
          cp ${extProfile} $out/etc/profile.d/11-ext-profile.sh
        '')
      ]
    );
    pathsToLink = lib.lists.unique (
      pathsToLink ++ [ "/etc/profile.d" ] ++ (map (x: "${x}") extensions) ++ [ "${pkgs.jq}" ]
    );
  };
  runAsRoot = ''
    #!${pkgs.runtimeShell}
    ${pkgs.dockerTools.shadowSetup}

    if ! id "${username}"; then
      useradd -m -g ${username} -s /usr/bin/bash ${username}
    fi
    mkdir /workspaces
    chown -R ${username}:users /workspaces
  '';
}
