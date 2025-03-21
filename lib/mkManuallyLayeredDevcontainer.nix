{
  pkgs,
  name,

  username ? "vscode",
  group ? username,
  uid ? 1000,
  gid ? uid,

  tag ? "latest",
  timeZone ? "UTC",
  # !!! it makes the whole /nix writable
  withNix ? false,
  features ? [ ],
}:
let
  lib = pkgs.lib;

  mkExtensions =
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

    # # execute the command without a shell
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
    "files.eol" = "\n";
  };

  vscodeSettingsFull =
    builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) vscodeSettingsDefault
      (map (v: v.vscodeSettings) (lib.filter (feat: builtins.hasAttr "vscodeSettings" feat) featuresVal));

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
    # This file is read for login shells.
    # Only execute this file once per shell.
    if [ -n "$__ETC_PROFILE_SOURCED" ]; then return; fi
    __ETC_PROFILE_SOURCED=1
    # Prevent this file from being sourced by interactive non-login child shells.
    export __ETC_PROFILE_DONE=1

    if [ "${"$"}{PS1-}" ]; then
      if [ "${"$"}{BASH-}" ] && [ "$BASH" != "/bin/sh" ]; then
        if [ -f /etc/bash.bashrc ]; then
          . /etc/bashrc
        fi
      fi
    fi

    if [ -d /etc/profile.d ]; then
      for i in /etc/profile.d/*.sh; do
        if [ -r $i ]; then
          . $i 2>&1 | tee -a "$HOME/.profile.log"
        fi
      done
      unset i
    fi
  '';

  aliasDefault = {
    l = "ls -alh";
    ll = "ls -l";
    ls = "ls --color=tty";
    ".." = "cd ..";
    mv = "mv -v";
  };

  aliasFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) aliasDefault (
    map (v: v.alias) (lib.filter (feat: builtins.hasAttr "alias" feat) featuresVal)
  );

  bashrcFile = pkgs.writeScript "bashrc" ''
        # Only execute this file once per shell.
        if [ -n "$__ETC_BASHRC_SOURCED" ] || [ -n "$NOSYSBASHRC" ]; then return; fi
        __ETC_BASHRC_SOURCED=1

        # If the profile was not loaded in a parent process, source
        # it.  But otherwise don't do it because we don't want to
        # clobber overridden values of $PATH, etc.
        if [ -z "$__ETC_PROFILE_DONE" ]; then
            . /etc/profile
        fi

        # We are not always an interactive shell.
        if [ -n "$PS1" ]; then

            # Check the window size after every command.
            shopt -s checkwinsize
            # Disable hashing (i.e. caching) of command lookups.
            set +h
            # Provide a nice prompt if the terminal supports it.
            if [ "$TERM" != "dumb" ] || [ -n "$INSIDE_EMACS" ]; then
                PROMPT_COLOR="1;31m"
                ((UID)) && PROMPT_COLOR="1;32m"
                if [ -n "$INSIDE_EMACS" ] || [ "$TERM" = "eterm" ] || [ "$TERM" = "eterm-color" ]; then
                    # Emacs term mode doesn't support xterm title escape sequence (\e]0;)
                    PS1="\[\033[$PROMPT_COLOR\][\u@\h:\w]\\$\[\033[0m\] "
                else
                    PS1="\[\033[$PROMPT_COLOR\][\[\e]0;\u@\h: \w\a\]\u@\h:\w]\\$\[\033[0m\] "
                fi
                if test "$TERM" = "xterm"; then
                    PS1="\[\033]2;\h:\u:\w\007\]$PS1"
                fi
            fi

            eval "$(${pkgs.coreutils}/bin/dircolors -b )"

            # Check whether we're running a version of Bash that has support for
            # programmable completion. If we do, enable all modules installed in
            # the system and user profile in obsolete /etc/bash_completion.d/
            # directories. Bash loads completions in all
            # $XDG_DATA_DIRS/bash-completion/completions/
            # on demand, so they do not need to be sourced here.
            if shopt -q progcomp &>/dev/null; then
                . "${pkgs.bash-completion}/etc/profile.d/bash_completion.sh"
                nullglobStatus=$(shopt -p nullglob)
                shopt -s nullglob
                for p in $NIX_PROFILES; do
                    for m in "$p/etc/bash_completion.d/"*; do
                        . "$m"
                    done
                done
                eval "$nullglobStatus"
                unset nullglobStatus p m
            fi

    ${builtins.concatStringsSep "\n" (
      map (aliasName: "alias -- ${aliasName}='${aliasFull."${aliasName}"}'") (
        builtins.attrNames aliasFull
      )
    )}

    ${builtins.concatStringsSep "\n" (map (feat: feat.bashrc or "") featuresVal)}

        fi
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

  essentialExecutablesRequried = with pkgs; [
    bash
    coreutils
    gnutar
    gzip
    gnused
    gnugrep
  ];

  # customExecutables = lib.lists.sort (a: b: (a.name or "${a}") < (b.name or "${b}")) (
  #   lib.filter (
  #     x:
  #     lib.lists.mutuallyExclusive [ x ] essentialExecutablesRequried
  #   ) (lib.lists.unique executables)
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
    LC_ALL = "en_US.UTF-8";
    TZDIR = "/etc/zoneinfo";
    LOCALE_ARCHIVE = "${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive";

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

  mkProfileScript =
    profileName: once: command:
    pkgs.writeScript "${profileName}" ''
      mkdir -p $HOME/state

      ${
        if once then
          ''
            if [ ! -f "$HOME/state/.${profileName}" ]; then
              echo executing ${profileName}
              ${command}

              touch "$HOME/state/.${profileName}"
            fi
          ''
        else
          ''
            echo executing ${profileName}
            ${command}
          ''
      }
    '';

  metadataFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) metadataDefault (
    (map (v: v.metadata) (
      lib.filter (
        feat: builtins.hasAttr "metadata" feat && builtins.length (builtins.attrNames feat.metadata) > 0
      ) featuresVal
    ))
    ++ [
      { customizations.vscode.settings = vscodeSettingsFull; }
    ]
  );
in
pkgs.nix2container.buildImage {
  inherit name tag;
  initializeNixDatabase = true;
  nixUid = if withNix then uid else null;
  nixGid = if withNix then gid else null;

  # https://github.com/docker/docs/issues/8230#issuecomment-468630187
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
    # {
    #   regex = "/vscode";
    #   mode = "0744";
    #   uid = uid;
    #   gid = gid;
    # }
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
                (pkgs.runCommand "profile" { } ''
                  mkdir -p $out/etc
                  ln -s ${profileFile} $out/etc/profile
                '')
                osRelease
              ];
            pathsToLink = [ "/etc" ];
          }

          # nixos/modules/config/locale.nix
          {
            name = "set timezone";
            paths = [
              (pkgs.runCommand "zoneinfo" { } ''
                mkdir -p $out/etc
                ln -s ${pkgs.tzdata}/share/zoneinfo $out/etc/zoneinfo
                ln -s ${pkgs.tzdata}/share/zoneinfo/${timeZone} $out/etc/localtime
              '')
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
            name = "essential executables required by vscode";
            paths = essentialExecutablesRequried;
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

                    ln -s ${
                      mkProfileScript profileName true ''
                        set -x

                        if [ "$CODESPACES" == "true" ]; then
                          VSCODE_DIR=".vscode-remote"
                        else
                          VSCODE_DIR=".vscode-server"
                        fi

                        mkdir -p $HOME/$VSCODE_DIR/extensions

                        if [ ! -f $HOME/$VSCODE_DIR/extensions/extensions.json ]; then
                          echo '[]' > $HOME/$VSCODE_DIR/extensions/extensions.json
                        fi

                        echo '${builtins.toJSON (mkExtensions extensions)}' > "/tmp/${profileName}.json"
                        ALL="$(jq -s '.[0] + .[1]' "/tmp/${profileName}.json" $HOME/$VSCODE_DIR/extensions/extensions.json)"
                        echo "$ALL" > $HOME/$VSCODE_DIR/extensions/extensions.json
                        rm "/tmp/${profileName}.json"
                      ''
                    } $out/etc/profile.d/11-${profileName}.sh
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
                (map (library: {
                  name = "feat:${feat.name}:lib:${library.name or "${library}"}";
                  paths = [ library ];
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
                (map (exe: {
                  name = "feat:${feat.name}:exe:${exe.name or "${exe}"}";
                  paths = [ exe ];
                  pathsToLink = [ "/bin" ];
                }) feat.executables)
              else
                [
                  {
                    name = "feat:${feat.name}:exe";
                    paths = feat.executables;
                    pathsToLink = [ "/bin" ];
                  }
                ]
            )
            (
              lib.filter (
                feat: builtins.hasAttr "executables" feat && builtins.length feat.executables > 0
              ) featuresVal
            )
        ))

        ++ (map
          (
            feat:
            let
              profileNamePrefix = "feat:${feat.name}:onLogin";
              profilePkg = pkgs.runCommand profileNamePrefix { } ''
                mkdir -p $out/etc/profile.d

                ln -s ${pkgs.writeScript "${profileNamePrefix}" ''
                  set -x

                  ${builtins.concatStringsSep "\n" (
                    map (
                      onLoginName:
                      let
                        onLogin = feat.onLogin."${onLoginName}";
                      in
                      mkProfileScript "${profileNamePrefix}:${onLoginName}" (onLogin.once or false) onLogin.command
                    ) (builtins.attrNames feat.onLogin)
                  )}

                ''} $out/etc/profile.d/11-${profileNamePrefix}.sh
              '';
            in
            {
              name = profileNamePrefix;
              paths = [ profilePkg ];
              pathsToLink = [ "/etc/profile.d" ];
            }
          )
          (
            lib.filter (
              feat: builtins.hasAttr "onLogin" feat && builtins.length (builtins.attrNames feat.onLogin) > 0
            ) featuresVal
          )
        )

        ++ [
          {
            name = "bashrc";
            paths = [
              (pkgs.runCommand "bashrc" { } ''
                mkdir -p $out/etc
                ln -s ${bashrcFile} $out/etc/bashrc
              '')
            ];
            pathsToLink = [ "/etc" ];
          }
        ];

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
