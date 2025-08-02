{
  pkgs,
  name,
  tag ? "latest",
  packages ? [ ],
  libraries ? [ ],
  extensions ? [ ],
  envVars ? { },
  vscodeSettings ? { },
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

  vscodeSettingsFull = lib.attrsets.recursiveUpdate {
    "git.enabled" = true;
    "git.enableSmartCommit" = false;
    "git.enableCommitSigning" = false;
    "git.enableStatusBarSync" = false;
    "git.openRepositoryInParentFolders" = "always";
    "diffEditor.wordWrap" = "on";
    "editor.formatOnSave" = false;
    "editor.formatOnType" = false;
    "editor.wordWrap" = "on";
    "workbench.localHistory.enabled" = false;
    "remote.autoForwardPortsSource" = "hybrid";
    # "editor.fontFamily" = "'JetBrainsMono Nerd Font', 'monospace', monospace";
    # "editor.tabSize" = 2;

  } vscodeSettings;

  # nixos/modules/misc/version.nix
  osReleaseFile =
    let
      trivial = pkgs.lib.trivial;
      cfg = {
        inherit (trivial) release codeName;
        distroName = "NixOS";
        distroId = "nixos";
        vendorName = "NixOS";
      };
      osReleaseContents = {
        PRETTY_NAME = "${cfg.distroName} ${cfg.release} (${cfg.codeName})";
        NAME = "${cfg.distroName}";
        VERSION_ID = cfg.release;
        VERSION = "${cfg.release} (${cfg.codeName})";
        VERSION_CODENAME = lib.toLower cfg.codeName;
        ID = "${cfg.distroId}";
        HOME_URL = "https://nixos.org/";
        SUPPORT_URL = "https://nixos.org/community.html";
        BUG_REPORT_URL = "https://github.com/NixOS/nixpkgs/issues";
      };

      needsEscaping = s: null != builtins.match "[a-zA-Z0-9]+" s;
      escapeIfNecessary = s: if needsEscaping s then s else ''"${lib.escape [ "$" "\"" "\\" "`" ] s}"'';
      attrsToText =
        attrs:
        builtins.concatStringsSep "\n" (
          lib.mapAttrsToList (n: v: ''${n}=${escapeIfNecessary (toString v)}'') attrs
        )
        + "\n";
    in
    pkgs.writeText "os-release" (attrsToText osReleaseContents);
  osRelease = pkgs.runCommand "os-release" { } ''
    mkdir -p $out/etc
    ln -s ${osReleaseFile} $out/etc/os-release
  '';

  profileFile = pkgs.writeShellScript "profile" ''
    if [ -d /etc/profile.d ]; then
      for i in /etc/profile.d/*.sh; do
        if [ -r $i ]; then
          . $i
        fi
      done
      unset i
    fi
  '';
  profile = pkgs.runCommand "profile" { } ''
    mkdir -p $out/etc
    ln -s ${profileFile} $out/etc/profile
  '';

  extProfileFile = pkgs.writeShellScript "ext-profile" ''
    if [ -f $HOME/.ext-profile ]; then
      exit 0
    fi
    touch $HOME/.ext-profile

    if [ "$CODESPACES" == "true" ]; then
      VSCODE_DIR=".vscode-remote"
    else
      VSCODE_DIR=".vscode-server"
    fi

    mkdir -p $HOME/$VSCODE_DIR/extensions
    if [ ! -f $HOME/$VSCODE_DIR/extensions/extensions.json ]; then
      echo '[]' > $HOME/$VSCODE_DIR/extensions/extensions.json
    fi
    cat > /tmp/extensions.json <<EOF
    ${builtins.toJSON extensionsJson}
    EOF
    ALL="$(jq -s '.[0] + .[1]' /tmp/extensions.json $HOME/$VSCODE_DIR/extensions/extensions.json)"
    echo "$ALL" > $HOME/$VSCODE_DIR/extensions/extensions.json

    mkdir -p $HOME/$VSCODE_DIR/data/Machine
    cat > $HOME/$VSCODE_DIR/data/Machine/settings.json <<EOF
    ${builtins.toJSON vscodeSettingsFull}
    EOF

    chown -R ${username}:${username} $HOME
  '';
  extProfile = pkgs.runCommand "profile" { } ''
    mkdir -p $out/etc/profile.d
    ln -s ${extProfileFile} $out/etc/profile.d/11-ext-profile.sh
  '';

  # https://github.com/manesiotise/plutus-apps/blob/dbafa0ffdc1babcf8e9143ca5a7adde78d021a9a/nix/devcontainer-docker-image.nix#L99-L103
  # allow ubuntu ELF binaries to run. VSCode copies it's own.
  lib64 = pkgs.runCommand "lib64" { } ''
    mkdir -p $out/lib64
    ln -s ${pkgs.glibc}/lib64/ld-linux-x86-64.so.2 $out/lib64/ld-linux-x86-64.so.2
    ln -s ${pkgs.gcc-unwrapped.lib}/lib64/libstdc++.so.6 $out/lib64/libstdc++.so.6
  '';

  libs =
    (with pkgs; [
      glibc
      gcc-unwrapped.lib
      stdenv.cc.cc.lib
    ])
    ++ libraries;

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;

  envVarsFull = {
    # required by vscode terminal, but allow overriding
    SHELL = "/bin/bash";
  }
  // envVars
  // {
    # required by vscode-server and its node
    LD_LIBRARY_PATH = "${LD_LIBRARY_PATH}${
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

      git

      jq

      findutils
      iproute2
      iputils
      openssh

      fd
      ripgrep
      unzip
      zip
      (p7zip.override { enableUnfree = true; })
      vim
      wget
      curl
      file
      tree
      aria2
      openssl
      netcat

      procps
      gnupg
      lsof
      htop
      rsync
      bzip2
      xz
      less
      util-linux
    ])
    ++ [
      profile
      extProfile
      osRelease
      lib64
    ]
    ++ packages
  );

  extraCommands = ''
    mkdir -m 1777 tmp
  '';

  # https://github.com/devcontainers/features/blob/main/src/common-utils/main.sh
  fakeRootCommands = ''
    #!${pkgs.runtimeShell}
    set -eux

    ${pkgs.dockerTools.shadowSetup}

    groupadd --system --gid 1000 ${username}
    useradd -s /bin/bash --system --uid 1000 --gid ${username} -m ${username}

    mkdir -p /workspaces
    chown ${username}:${username} /workspaces
  '';
  enableFakechroot = true;
}
