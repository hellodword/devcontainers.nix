{
  pkgs,
  name,
  tag ? "latest",
  features ? [ ],
}:
let
  lib = pkgs.lib;

  username = "vscode";

  extensionsJson =
    exts:
    map (x: {
      identifier.id = x.vscodeExtUniqueId;
      version = x.version;
      location = {
        "$mid" = 1;
        scheme = "file";
        path = "${x}/share/vscode/extensions/${x.vscodeExtUniqueId}";
      };
    }) exts;

  # https://devcontainers.github.io/implementors/json_reference/
  metadataDefault = {
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
      # USER = username;
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

  };

  featuresVal = map (x: x { inherit pkgs envVarsDefault; }) features;

  metadataFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) metadataDefault (
    map (v: v.metadata) (
      lib.filter (
        feat: builtins.hasAttr "metadata" feat && builtins.length (builtins.attrNames feat.metadata) > 0
      ) featuresVal
    )
  );

  vscodeSettingsDefault = {
    "diffEditor.wordWrap" = "on";
    "editor.formatOnSave" = true;
    "editor.formatOnType" = false;
    "editor.wordWrap" = "on";
    "workbench.localHistory.enabled" = false;
    "remote.autoForwardPortsSource" = "hybrid";
    # "editor.fontFamily" = "'JetBrainsMono Nerd Font', 'monospace', monospace";
    "editor.tabSize" = 2;
    "extensions.ignoreRecommendations" = true;
  };

  vscodeSettingsFull =
    builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) vscodeSettingsDefault
      (
        map (v: v.vscodeSettings) (
          lib.filter (
            feat:
            builtins.hasAttr "vscodeSettings" feat
            && builtins.length (builtins.attrNames feat.vscodeSettings) > 0
          ) featuresVal
        )
      );

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

  # https://github.com/manesiotise/plutus-apps/blob/dbafa0ffdc1babcf8e9143ca5a7adde78d021a9a/nix/devcontainer-docker-image.nix#L99-L103
  # allow ubuntu ELF binaries to run. VSCode copies it's own.
  lib64 = pkgs.runCommand "lib64" { } ''
    mkdir -p $out/lib64
    ln -s ${pkgs.glibc}/lib64/ld-linux-x86-64.so.2 $out/lib64/ld-linux-x86-64.so.2
    ln -s ${pkgs.gcc-unwrapped.lib}/lib64/libstdc++.so.6 $out/lib64/libstdc++.so.6
  '';

  librariesDefault = with pkgs; [
    glibc
    gcc-unwrapped.lib
    stdenv.cc.cc.lib
  ];

  librariesFull = lib.lists.unique (
    librariesDefault
    ++ (lib.lists.concatLists (
      map (v: v.libraries) (
        lib.filter (
          feat: builtins.hasAttr "libraries" feat && builtins.length feat.libraries > 0
        ) featuresVal
      )
    ))
  );

  essentialPackagesRequried = with pkgs; [
    bash
    coreutils
    gnutar
    gzip
    gnused
    gnugrep
  ];

  # customPackages = lib.lists.sort (a: b: (a.name or "${a}") < (b.name or "${b}")) (
  #   lib.filter (
  #     x:
  #     lib.lists.mutuallyExclusive [ x ] (
  #       essentialPackagesRequried ++ essentialPackagesDevBase ++ essentialPackagesFreq ++ essentialPackages
  #     )
  #   ) (lib.lists.unique packages)
  # );

  # required by vscode-server and its node
  LD_LIBRARY_PATH_Default = pkgs.lib.makeLibraryPath librariesFull;

  LD_LIBRARY_PATH_Full =
    builtins.foldl'
      (
        x: y:
        builtins.concatStringsSep ":" [
          x
          y
        ]
      )
      LD_LIBRARY_PATH_Default
      (
        map (v: v.envVars.LD_LIBRARY_PATH) (
          lib.filter (
            feat:
            builtins.hasAttr "envVars" feat
            && builtins.hasAttr "LD_LIBRARY_PATH" feat.envVars
            && builtins.stringLength feat.envVars.LD_LIBRARY_PATH > 0
          ) featuresVal
        )
      );

  PKG_CONFIG_PATH_Default = pkgs.lib.makeSearchPath "lib/pkgconfig" librariesFull;

  PKG_CONFIG_PATH_Full =
    builtins.foldl'
      (
        x: y:
        builtins.concatStringsSep ":" [
          x
          y
        ]
      )
      PKG_CONFIG_PATH_Default
      (
        map (v: v.envVars.PKG_CONFIG_PATH) (
          lib.filter (
            feat:
            builtins.hasAttr "envVars" feat
            && builtins.hasAttr "PKG_CONFIG_PATH" feat.envVars
            && builtins.stringLength feat.envVars.PKG_CONFIG_PATH > 0
          ) featuresVal
        )
      );

  PATH_Default = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";

  PATH_Full =
    builtins.foldl'
      (
        x: y:
        builtins.concatStringsSep ":" [
          x
          y
        ]
      )
      PATH_Default
      (
        map (v: v.envVars.PATH) (
          lib.filter (
            feat:
            builtins.hasAttr "envVars" feat
            && builtins.hasAttr "PATH" feat.envVars
            && builtins.stringLength feat.envVars.PATH > 0
          ) featuresVal
        )
      );

  envVarsDefault = rec {
    # required by vscode terminal, but allow overriding
    SHELL = "/bin/bash";
    HOME = "/home/${username}";
    USER = username;
    LANG = "en_US.UTF-8";
    TZDIR = "/etc/zoneinfo";

    DO_NOT_TRACK = "true";

    XDG_BIN_HOME = "${HOME}/bin";
    XDG_CONFIG_HOME = "${HOME}/config";
    XDG_CACHE_HOME = "${HOME}/cache";
    XDG_DATA_HOME = "${HOME}/share";
    XDG_STATE_HOME = "${HOME}/state";

    XDG_USER_HOME = "/home";
    XDG_VAR_HOME = "${HOME}/var";

    XDG_DESKTOP_DIR = "${XDG_USER_HOME}/Desktop";
    XDG_DOCUMENTS_DIR = "${XDG_USER_HOME}/Documents";
    XDG_DOWNLOAD_DIR = "${XDG_USER_HOME}/Downloads";
    XDG_MUSIC_DIR = "${XDG_USER_HOME}/Music";
    XDG_PICTURES_DIR = "${XDG_USER_HOME}/Images";
    XDG_PUBLICSHARE_DIR = "${XDG_USER_HOME}/Shared";
    XDG_REPOSITORY_DIR = "${XDG_USER_HOME}/Repositories";
    XDG_TEMPLATES_DIR = "${XDG_USER_HOME}/Templates";
    XDG_VIDEOS_DIR = "${XDG_USER_HOME}/Videos";
  };

  envVarsList =
    [ envVarsDefault ]
    ++ (map (v: v.envVars) (lib.filter (feat: builtins.hasAttr "envVars" feat) featuresVal))
    ++ [

      {
        LD_LIBRARY_PATH = LD_LIBRARY_PATH_Full;
        PKG_CONFIG_PATH = PKG_CONFIG_PATH_Full;
        PATH = PATH_Full;
      }
    ];

  envVarsFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } envVarsList;

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
    Env = map (x: "${x}=${builtins.toString envVarsFull."${x}"}") (builtins.attrNames envVarsFull);
    Labels = {
      "devcontainer.metadata" = builtins.toJSON metadataFull;
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
                osRelease
              ];
            pathsToLink = [ "/etc" ];
          }

          {
            name = "tzdata";
            paths = with pkgs; [
              tzdata
            ];
            pathsToLink = [ "/etc" ];
          }

          {
            name = "required /lib64";
            paths = [ lib64 ];
            pathsToLink = [
              "/lib64"
            ];
          }

          {
            name = "default libraries";
            paths = librariesDefault;
            pathsToLink = [
              "/nix/store"
            ];
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
        ]

        ++ (lib.lists.concatLists (
          map
            (
              feat:
              let
                # TODO or download VSIX files and using `code --install-extension --force <foo.VSIX>`
                mkExtProfilePkg =
                  profileName: extensions:
                  pkgs.runCommand profileName { } ''
                    mkdir -p $out/etc/profile.d

                    ln -s ${pkgs.writeScript "${profileName}" ''

                      if [ "$CODESPACES" == "true" ]; then
                        VSCODE_DIR=".vscode-remote"
                      else
                        VSCODE_DIR=".vscode-server"
                      fi

                      mkdir -p $HOME/$VSCODE_DIR/extensions

                      mkdir -p $HOME/state

                      if [ ! -f "$HOME/state/.${profileName}" ]; then
                        if [ ! -f $HOME/$VSCODE_DIR/extensions/extensions.json ]; then
                          echo '[]' > $HOME/$VSCODE_DIR/extensions/extensions.json
                        fi

                        echo '${builtins.toJSON (extensionsJson extensions)}' > "/tmp/${profileName}.json"
                        ALL="$(jq -s '.[0] + .[1]' "/tmp/${profileName}.json" $HOME/$VSCODE_DIR/extensions/extensions.json)"
                        echo "$ALL" > $HOME/$VSCODE_DIR/extensions/extensions.json
                        rm "/tmp/${profileName}.json"

                        touch "$HOME/state/.${profileName}"
                      fi

                    ''} $out/etc/profile.d/11-${profileName}.sh
                  '';
              in
              if feat.layered or false then
                (map (ext: {
                  name = "feat:${feat.name}:ext:${ext.name}";
                  paths = [
                    (mkExtProfilePkg "feat:${feat.name}:ext:${ext.name}" [ ext ])
                  ];
                  pathsToLink = [ "/etc/profile.d" ];
                }) feat.extensions)
              else
                [
                  {
                    name = "feat:${feat.name}:ext";
                    paths = [
                      (mkExtProfilePkg "feat:${feat.name}:ext" feat.extensions)
                    ];
                    pathsToLink = [ "/etc/profile.d" ];
                  }
                ]
            )
            (
              lib.filter (
                feat: builtins.hasAttr "extensions" feat && builtins.length feat.extensions > 0
              ) featuresVal
            )
        ))

        ++ (lib.lists.concatLists (
          map
            (
              feat:
              if feat.layered or false then
                (map (pkg: {
                  name = "feat:${feat.name}:lib:${pkg.name or "${pkg}"}";
                  paths = [ pkg ];
                  pathsToLink = [ "/nix/store" ];
                }) feat.libraries)
              else
                [
                  {
                    name = "feat:${feat.name}:lib";
                    paths = feat.libraries;
                    pathsToLink = [ "/nix/store" ];
                  }
                ]
            )
            (
              lib.filter (
                feat: builtins.hasAttr "libraries" feat && builtins.length feat.libraries > 0
              ) featuresVal
            )
        ))

        ++ (lib.lists.concatLists (
          map
            (
              feat:
              if feat.layered or false then
                (map (pkg: {
                  name = "feat:${feat.name}:pkg:${pkg.name or "${pkg}"}";
                  paths = [ pkg ];
                  pathsToLink = [ "/bin" ];
                }) feat.packages)
              else
                [
                  {
                    name = "feat:${feat.name}:pkg";
                    paths = feat.packages;
                    pathsToLink = [ "/bin" ];
                  }
                ]
            )
            (
              lib.filter (feat: builtins.hasAttr "packages" feat && builtins.length feat.packages > 0) featuresVal
            )
        ))

        ++ [
          (
            let
              profileName = "settings-profile";
              profilePkg = pkgs.runCommand profileName { } ''
                mkdir -p $out/etc/profile.d

                ln -s ${pkgs.writeScript "${profileName}" ''

                  if [ "$CODESPACES" == "true" ]; then
                    VSCODE_DIR=".vscode-remote"
                  else
                    VSCODE_DIR=".vscode-server"
                  fi

                  mkdir -p $HOME/$VSCODE_DIR/data/Machine

                  mkdir -p $HOME/state

                  if [ ! -f "$HOME/state/.${profileName}" ]; then
                    echo '${builtins.toJSON vscodeSettingsFull}' > "$HOME/$VSCODE_DIR/data/Machine/settings.json"

                    touch "$HOME/state/.${profileName}"
                  fi
                ''} $out/etc/profile.d/11-${profileName}.sh
              '';
            in
            {
              name = profileName;
              paths = [ profilePkg ];
              pathsToLink = [ "/etc/profile.d" ];
            }
          )
        ]

        ++ (map
          (
            feat:
            let
              profileName = "feat:${feat.name}:onLogin";
              profilePkg = pkgs.runCommand profileName { } ''
                mkdir -p $out/etc/profile.d

                ln -s ${pkgs.writeScript "${profileName}" ''

                  mkdir -p $HOME/state

                  ${builtins.concatStringsSep "\n" (
                    map (onLogin: ''
                      ${
                        if onLogin.once then
                          ''
                            ${onLogin.command}
                          ''
                        else
                          ''
                            if [ ! -f "$HOME/state/.${profileName}:${onLogin.uniqueName}" ]; then
                              ${onLogin.command}

                              touch "$HOME/state/.${profileName}:${onLogin.uniqueName}"
                            fi
                          ''
                      }
                    '') feat.onLogin
                  )}

                ''} $out/etc/profile.d/11-${profileName}.sh
              '';
            in
            {
              name = profileName;
              paths = [ profilePkg ];
              pathsToLink = [ "/etc/profile.d" ];
            }
          )
          (lib.filter (feat: builtins.hasAttr "onLogin" feat && builtins.length feat.onLogin > 0) featuresVal)
        );

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
