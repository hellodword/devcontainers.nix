{
  pkgs,
  name,
  tag ? "latest",
  packages ? [ ],
  libraries ? [ ],
  extensions ? [ ],
  envVars ? { },
  vscodeSettings ? { },
  metadata ? { },
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
    "editor.tabSize" = 2;
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

  profileFile = pkgs.writeScript "profile" ''
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

  extProfileFile = pkgs.writeScript "ext-profile" ''
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
      # glibc
      # gcc-unwrapped.lib
      stdenv.cc.cc.lib
    ])
    ++ libraries;

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;

  essentialPackagesRequried = with pkgs; [
    bash
    coreutils
    gnutar
    gzip
    gnused
    gnugrep
  ];

  essentialPackagesDevBase = with pkgs; [
    git
    jq
    wget
    curl
  ];

  essentialPackagesFreq = with pkgs; [
    findutils
    iproute2
    iputils
    openssh
    which
    unzip
    zip
    vim
    file
    tree
    bzip2
    xz
    less
    lsof
    htop
  ];

  essentialPackages = with pkgs; [
    fd
    ripgrep
    (p7zip.override { enableUnfree = true; })

    aria2
    openssl
    netcat

    procps
    gnupg
    rsync
    util-linux
  ];

  customPackages = lib.lists.sort (a: b: (a.name or "${a}") < (b.name or "${b}")) (
    lib.filter (
      x:
      lib.lists.mutuallyExclusive [ x ] (
        essentialPackagesRequried ++ essentialPackagesDevBase ++ essentialPackagesFreq ++ essentialPackages
      )
    ) (lib.lists.unique packages)
  );

  envVarsFull =
    {
      # required by vscode terminal, but allow overriding
      SHELL = "/bin/bash";
    }
    // envVars
    // {
      # required by vscode-server and its node
      LD_LIBRARY_PATH = "${LD_LIBRARY_PATH}${
        if builtins.hasAttr "LD_LIBRARY_PATH" envVars then ":${envVars.LD_LIBRARY_PATH}" else ""
      }";
      PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
    };

  mkTmp = pkgs.runCommand "container-tmp" { } ''
    mkdir -p $out/tmp
  '';

  group = username;
  uid = 1000;
  gid = uid;

  mkUser = (
    pkgs.runCommand "mkUser" { } ''
      mkdir -p $out/etc/pam.d

      echo "root:x:0:0:System administrator:/root:/bin/bash" > \
            $out/etc/passwd
      echo "${username}:x:${builtins.toString uid}:${builtins.toString gid}::/home/${username}:/bin/bash" >> \
            $out/etc/passwd

      echo "root:!x:::::::" > $out/etc/shadow
      echo "${username}:!x:::::::" >> $out/etc/shadow

      echo "root:x:0:" > $out/etc/group
      echo "${group}:x:${builtins.toString gid}:" >> $out/etc/group

      cat > $out/etc/pam.d/other <<EOF
      account sufficient pam_unix.so
      auth sufficient pam_rootok.so
      password requisite pam_unix.so nullok sha512
      session required pam_unix.so
      EOF

      touch $out/etc/login.defs
      mkdir -p $out/home/${username}
    ''
  );

in
pkgs.nix2container.buildImage {
  inherit name tag;
  initializeNixDatabase = true;

  maxLayers = 100;

  perms = [
    {
      path = mkTmp;
      mode = "1777";
    }
    {
      path = mkUser;
      regex = "/home/${username}";
      mode = "0744";
      uid = uid;
      gid = gid;
      uname = username;
      gname = group;
    }
  ];

  copyToRoot = [
    mkTmp
    mkUser
  ];

  config = {
    User = "${username}:${username}";
    Env = map (x: "${x}=${envVarsFull."${x}"}") (builtins.attrNames envVarsFull);
    Labels = {
      # https://devcontainers.github.io/implementors/json_reference/
      "devcontainer.metadata" = builtins.toJSON (
        lib.attrsets.recursiveUpdate {
          # forwardPorts = [ ];
          # portsAttributes = {
          #   "3000" = {
          #     label = "Application port";
          #     protocol = "https";
          #     onAutoForward = "ignore";
          #     requireLocalPort = true;
          #     elevateIfNeeded = false;
          #   };
          # };
          # otherPortsAttributes = {
          #   "onAutoForward" = "silent";
          # };
          containerEnv = {
            USER = username;
          };
          # remoteEnv = { };
          remoteUser = username;
          # containerUser = "root";
          # userEnvProbe = "loginInteractiveShell";
          # overrideCommand = true;
          # shutdownAction = "stopContainer";
          # init = false;
          privileged = false;

          # capAdd = [ ];
          # securityOpt = [ ];
          # mounts = [ ];
          # customizations = { };

          # onCreateCommand = '''';
          # updateContentCommand = '''';
          # postCreateCommand = '''';
          # postStartCommand = '''';
          # postAttachCommand = '''';
          # waitFor = "updateContentCommand";
          # hostRequirements = {
          #   cpus = 2;
          #   memory = "4gb";
          #   storage = "32gb";
          #   gpu = "optional";
          # };

          updateRemoteUserUID = false;

        } metadata
      );
    };
  };

  layers =
    let
      layersList =
        [
          {
            name = "/etc/* required by devcontainers";
            paths =
              (with pkgs.dockerTools; [
                caCertificates
              ])
              ++ [
                profile
                extProfile
                osRelease
              ];
            pathsToLink = [ "/etc" ];
          }

          {
            name = "/lib64";
            paths = [ lib64 ];
            pathsToLink = [ "/lib64" ];
          }

          {
            name = "/usr/bin/env";
            paths = [ pkgs.dockerTools.usrBinEnv ];
            pathsToLink = [ "/usr/bin" ];
          }

          {
            name = "essential packages required by vscode";
            paths = essentialPackagesRequried;
            pathsToLink = [ "/bin" ];
          }

          {
            name = "essential packages dev base";
            paths = essentialPackagesDevBase;
            pathsToLink = [ "/bin" ];
          }

          {
            name = "essential packages freq";
            paths = essentialPackagesFreq;
            pathsToLink = [ "/bin" ];
          }

          {
            name = "essential packages";
            paths = essentialPackages;
            pathsToLink = [ "/bin" ];
          }
        ]
        ++ (map (pkg: {
          name = pkg.name or "${pkg}";
          paths = [ pkg ];
          pathsToLink = [ "/bin" ];
        }) customPackages);

    in
    builtins.foldl' (
      layersList: el:
      let
        layer = pkgs.nix2container.buildLayer {
          metadata = {
            author = el.name;
            created_by = el.name;
            comment = el.name;
          };
          copyToRoot = pkgs.buildEnv {
            inherit (el) name paths pathsToLink;
          };
          layers = layersList;
        };
      in
      layersList ++ [ layer ]
    ) [ ] layersList;
}
