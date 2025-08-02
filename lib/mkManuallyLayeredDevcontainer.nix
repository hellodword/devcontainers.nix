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
  /*
    {
      name = "foo";

      layered = true;

      users = {
        foo = {
          uid = 1001;
          shell = "${pkgs.bashInteractive}/bin/bash";
          home = "/home/foo";
          gid = 1001;
          groups = [ "foo" ];
          # description = "foo user";
        };
      };
      groups = {
        foo.gid = 1001;
      };

      libraries = [];
      executables = [];
      deps = [];

      extensions = [];

      envVars = {
        FOO = "bar";
      };
      vscodeSettings = {};
      metadata = {};

      bashrc = '''';
      onLogin = {
        "dart disable analytics" = {
          command = "dart --disable-analytics || true";
          once = true;
        };
      };
      alias = {
        ll = "ls -l";
      };

      layers = [
        {
          deps = [];
        }
        # for copyToRoot
        {
          paths = [];
          pathsToLink = [];
        }
      ];
    }
  */
  features ? [ ],
}:
let
  lib = pkgs.lib;

  featureDefault = {
    name = "default";
    layered = false;

    users = {
      root = {
        uid = 0;
        shell = "${pkgs.bashInteractive}/bin/bash";
        home = "/root";
        gid = 0;
        groups = [ "root" ];
        description = "System administrator";
      };

      ${username} = {
        uid = uid;
        shell = "${pkgs.bashInteractive}/bin/bash";
        home = "/home/${username}";
        gid = gid;
        groups = [ username ];
        description = "default user";
      };
    };

    groups = {
      root.gid = 0;
      ${username}.gid = gid;
    };

    libraries = [ ];
    executables = [ pkgs.bashInteractive ];

    layers = [
      {
        name = "packages for base system";
        deps = featureDefault.libraries ++ featureDefault.executables;
      }
      {
        name = "base system";
        copyToRoot = mkBaseSystem;
        perms = [
          {
            path = mkBaseSystem;
            regex = "/tmp";
            mode = "1777";
          }
          {
            path = mkBaseSystem;
            regex = "/home/${username}";
            mode = "0744";
            uid = uid;
            gid = gid;
            uname = username;
            gname = group;
          }
        ];
      }
    ];

    envVars = envVarsDefault;

    # https://gcc.gnu.org/onlinedocs/gcc-14.2.0/gcc/Environment-Variables.html
    # https://clang.llvm.org/docs/CommandGuide/clang.html#environment
    # C_INCLUDE_PATH
    # CPLUS_INCLUDE_PATH
    # CMAKE_LIBRARY_PATH
    # CMAKE_INCLUDE_PATH
    envVarsFunc = {
      PATH =
        feat:
        (
          if
            builtins.hasAttr "envVars" feat
            && builtins.hasAttr "PATH" feat.envVars
            && builtins.stringLength feat.envVars.PATH > 0
          then
            feat.envVars.PATH + ":"
          else
            ""
        )
        + (lib.makeBinPath (feat.executables or [ ]));

      LD_LIBRARY_PATH =
        feat:
        (
          if
            builtins.hasAttr "envVars" feat
            && builtins.hasAttr "LD_LIBRARY_PATH" feat.envVars
            && builtins.stringLength feat.envVars.LD_LIBRARY_PATH > 0
          then
            feat.envVars.LD_LIBRARY_PATH + ":"
          else
            ""
        )
        + (lib.makeLibraryPath (feat.libraries or [ ]));

      PKG_CONFIG_PATH =
        feat:
        (
          if
            builtins.hasAttr "envVars" feat
            && builtins.hasAttr "PKG_CONFIG_PATH" feat.envVars
            && builtins.stringLength feat.envVars.PKG_CONFIG_PATH > 0
          then
            feat.envVars.PKG_CONFIG_PATH + ":"
          else
            ""
        )
        + (lib.makeSearchPath "lib/pkgconfig" (feat.libraries or [ ]));
    };

    alias = {
      l = "ls -alh";
      ll = "ls -l";
      ls = "ls --color=tty";
      ".." = "cd ..";
      mv = "mv -v";
    };

    vscodeSettings = {
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
      "github.gitAuthentication" = false;
      "github.branchProtection" = false;
      "github.showAvatar" = false;
    };

    # https://devcontainers.github.io/implementors/json_reference/
    metadata = {
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
  };

  featureVSCodeRuntime = {
    name = "vscode-runtime";
    layered = false;

    deps = with pkgs; [
      glibc
      cacert
    ];
    libraries = [
      # required by vscode-server and its node
      pkgs.stdenv.cc.cc.lib
    ];
    executables = with pkgs; [
      coreutils
      gnutar
      gzip
      gnused
      gnugrep
    ];

    layers = [
      {
        name = "packages for vscode runtime";
        deps =
          featureVSCodeRuntime.deps ++ featureVSCodeRuntime.libraries ++ featureVSCodeRuntime.executables;
      }
      {
        name = "vscode runtime";
        paths = [
          pkgs.dockerTools.caCertificates
          pkgs.dockerTools.binSh
          pkgs.dockerTools.usrBinEnv
          binBash
          osRelease
        ];
        pathsToLink = [
          "/bin"
          "/usr/bin"
          "/etc"
        ];
      }
      {
        name = "/lib64 for vscode runtime";
        paths = [ lib64 ];
        pathsToLink = [ "/lib64" ];
      }
    ];
  };

  featureInit = {
    name = "init";
    layered = false;

    deps = with pkgs; [
      bash-completion
      tzdata
    ];
    layers = [
      {
        name = "packages for init";
        deps = featureInit.deps;
      }
      {
        name = "init";
        paths = [
          profileFile

          bashrcFile

          # not necessary
          # nixos/modules/config/locale.nix
          (pkgs.runCommand "zoneinfo" { } ''
            mkdir -p $out/etc
            ln -s ${pkgs.tzdata}/share/zoneinfo $out/etc/zoneinfo
            ln -s ${pkgs.tzdata}/share/zoneinfo/${timeZone} $out/etc/localtime
          '')
        ];
        pathsToLink = [ "/etc" ];
      }
    ];
  };

  featuresVal = [
    featureDefault
    featureVSCodeRuntime
    featureInit
  ]
  ++ (map (x: x { inherit pkgs envVarsDefault; }) features);

  envVarsFuncFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } (
    map (v: v.envVarsFunc or { }) featuresVal
  );

  #####################################################
  ################### base system #####################

  usersFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } (
    map (v: v.users or { }) featuresVal
  );

  groupsFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } (
    map (v: v.groups or { }) featuresVal
  );

  userToPasswd = (
    k:
    {
      uid,
      gid ? 65534,
      home ? "/var/empty",
      description ? "",
      shell ? "/bin/false",
      ...
    }:
    "${k}:x:${toString uid}:${toString gid}:${description}:${home}:${shell}"
  );
  passwdContents = (lib.concatStringsSep "\n" (lib.attrValues (lib.mapAttrs userToPasswd usersFull)));

  userToShadow = k: { ... }: "${k}:!:1::::::";
  shadowContents = (lib.concatStringsSep "\n" (lib.attrValues (lib.mapAttrs userToShadow usersFull)));

  # Map groups to members
  # {
  #   group = [ "user1" "user2" ];
  # }
  groupMemberMap = (
    let
      # Create a flat list of user/group mappings
      mappings = (
        builtins.foldl' (
          acc: user:
          let
            groups = usersFull.${user}.groups or [ ];
          in
          acc ++ map (group: { inherit user group; }) groups
        ) [ ] (lib.attrNames usersFull)
      );
    in
    (builtins.foldl' (
      acc: v: acc // { ${v.group} = acc.${v.group} or [ ] ++ [ v.user ]; }
    ) { } mappings)
  );

  groupToGroup =
    k:
    { gid }:
    let
      members = groupMemberMap.${k} or [ ];
    in
    "${k}:x:${toString gid}:${lib.concatStringsSep "," members}";
  groupContents = (lib.concatStringsSep "\n" (lib.attrValues (lib.mapAttrs groupToGroup groupsFull)));

  mkBaseSystem =
    pkgs.runCommand "base-system"
      {
        inherit
          passwdContents
          groupContents
          shadowContents
          ;
        passAsFile = [
          "passwdContents"
          "groupContents"
          "shadowContents"
        ];
        allowSubstitutes = false;
        preferLocalBuild = true;
      }
      ''
        env
        set -x

        mkdir -p $out/etc

        cat $passwdContentsPath > $out/etc/passwd
        echo "" >> $out/etc/passwd

        cat $groupContentsPath > $out/etc/group
        echo "" >> $out/etc/group

        cat $shadowContentsPath > $out/etc/shadow
        echo "" >> $out/etc/shadow

        mkdir -p $out/tmp

        mkdir -p $out/home/${username}

        ${builtins.concatStringsSep "\n" (
          map (key: "mkdir -p $out${envVarsDefault."${key}"}") (
            lib.filter (key: lib.strings.hasPrefix "XDG_" key) (builtins.attrNames envVarsDefault)
          )
        )}
      '';

  #####################################################
  ################# vscode runtime ####################

  # nixos/modules/misc/version.nix
  osReleaseContents =
    let
      trivial = pkgs.lib.trivial;
      cfg = {
        inherit (trivial) release codeName;
        distroName = "NixOS";
        distroId = "nixos";
        vendorName = "NixOS";
      };
      osReleaseAttrs = {
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
    attrsToText osReleaseAttrs;
  osRelease =
    pkgs.runCommand "os-release"
      {
        inherit
          osReleaseContents
          ;
        passAsFile = [
          "osReleaseContents"
        ];
        allowSubstitutes = false;
        preferLocalBuild = true;
      }
      ''
        mkdir -p $out/etc
        cat $osReleaseContentsPath > $out/etc/os-release
      '';

  # TODO https://github.com/microsoft/vscode/blob/3dcca830e652b47f80991b400a269cd4d1b3e9e7/resources/server/bin/helpers/check-requirements-linux.sh#L16-L24
  # https://github.com/manesiotise/plutus-apps/blob/dbafa0ffdc1babcf8e9143ca5a7adde78d021a9a/nix/devcontainer-docker-image.nix#L99-L103
  # allow ubuntu ELF binaries to run. VSCode copies it's own.
  # ln -s ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6 $out/lib64/libstdc++.so.6
  lib64 = pkgs.runCommand "lib64" { } ''
    mkdir -p $out/lib64
    ln -s ${pkgs.glibc}/lib64/ld-linux-x86-64.so.2 $out/lib64/ld-linux-x86-64.so.2
  '';

  # required by vscode-node and GDB
  binBash = pkgs.runCommand "bin-bash" { } ''
    mkdir -p $out/bin
    ln -s ${pkgs.bashInteractive}/bin/bash $out/bin/bash
  '';

  #####################################################
  ################# profile bashrc ####################

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

  vscodeSettingsFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } (
    map (v: v.vscodeSettings or { }) featuresVal
  );

  profileContents = ''
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
          . $i >> "$HOME/.profile.log" 2>&1
        fi
      done
      unset i
    fi
  '';

  profileFile =
    pkgs.runCommand "profile"
      {
        inherit
          profileContents
          ;
        passAsFile = [
          "profileContents"
        ];
        allowSubstitutes = false;
        preferLocalBuild = true;
      }
      ''
        mkdir -p $out/etc
        cat $profileContentsPath > $out/etc/profile
        chmod +x $out/etc/profile
      '';

  aliasFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } (
    map (v: v.alias or { }) featuresVal
  );

  bashrcContents = ''
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

  bashrcFile =
    pkgs.runCommand "bashrc"
      {
        inherit
          bashrcContents
          ;
        passAsFile = [
          "bashrcContents"
        ];
        allowSubstitutes = false;
        preferLocalBuild = true;
      }
      ''
        mkdir -p $out/etc
        cat $bashrcContentsPath > $out/etc/bashrc
        chmod +x $out/etc/bashrc
      '';

  #####################################################
  ######################## env ########################

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

    # https://specifications.freedesktop.org/basedir-spec/latest/
    # https://www.freedesktop.org/wiki/Software/xdg-user-dirs/
    # https://gist.github.com/roalcantara/107ba66dfa3b9d023ac9329e639bc58c

    XDG_CACHE_HOME = "${HOME}/.cache";
    # XDG_CONFIG_DIRS
    XDG_CONFIG_HOME = "${HOME}/.config";
    # XDG_DATA_DIRS
    XDG_DATA_HOME = "${HOME}/.local/share";
    # XDG_RUNTIME_DIR
    XDG_STATE_HOME = "${HOME}/.local/state";

    XDG_USER_HOME = "/home";
    XDG_BIN_HOME = "${HOME}/.local/bin";
    XDG_VAR_HOME = "${HOME}/.local/var";
    XDG_OPT_HOME = "${HOME}/.local/opt";
    XDG_LIB_HOME = "${HOME}/.local/lib";
    XDG_SRC_HOME = "${HOME}/.local/src";

    XDG_DESKTOP_DIR = "${XDG_USER_HOME}/Desktop";
    XDG_DOCUMENTS_DIR = "${XDG_USER_HOME}/Documents";
    XDG_DOWNLOAD_DIR = "${XDG_USER_HOME}/Downloads";
    XDG_MUSIC_DIR = "${XDG_USER_HOME}/Music";
    XDG_PICTURES_DIR = "${XDG_USER_HOME}/Pictures";
    XDG_PUBLICSHARE_DIR = "${XDG_USER_HOME}/Public";
    XDG_REPOSITORY_DIR = "${XDG_USER_HOME}/Repositories";
    XDG_TEMPLATES_DIR = "${XDG_USER_HOME}/Templates";
    XDG_VIDEOS_DIR = "${XDG_USER_HOME}/Movies";
  };

  envVarsNormal = (map (v: v.envVars or { }) featuresVal);
  envVarsSpecial = map (k: {
    "${k}" = builtins.concatStringsSep ":" (
      lib.filter (s: builtins.stringLength s > 0) (map (feat: envVarsFuncFull."${k}" feat) featuresVal)
    );
  }) (builtins.attrNames envVarsFuncFull);
  envVarsFull = builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } (
    envVarsNormal ++ envVarsSpecial
  );

  #####################################################
  #################### metadata ######################

  metadataOnCreateCommand = builtins.concatStringsSep "\n" (
    [
      "/etc/profile"
    ]
    ++ (map (v: v.metadata.onCreateCommand) (
      lib.filter (
        feat: builtins.hasAttr "metadata" feat && builtins.hasAttr "onCreateCommand" feat.metadata
      ) featuresVal
    ))
  );

  metadataFull =
    (builtins.foldl' (x: y: lib.attrsets.recursiveUpdate x y) { } (
      (map (v: v.metadata or { }) featuresVal)
      ++ [
        { customizations.vscode.settings = vscodeSettingsFull; }
      ]
    ))
    // {
      onCreateCommand = metadataOnCreateCommand;
    };
in
pkgs.nix2container.buildImage {
  inherit name tag;
  initializeNixDatabase = true;
  nixUid = if withNix then uid else null;
  nixGid = if withNix then gid else null;

  # https://github.com/docker/docs/issues/8230#issuecomment-468630187
  maxLayers = 127;

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
        (lib.lists.concatLists (
          map (
            feat:
            let
              packages = (feat.deps or [ ]);
            in
            if builtins.length packages == 0 then
              [ ]
            else if feat.layered or false then
              (map (package: {
                name = "feat:${feat.name or "unknown"}:${package.name}";
                deps = [ package ];
              }) packages)
            else
              [
                {
                  name = "feat:${feat.name or "unknown"}";
                  deps = packages;
                }
              ]
          ) featuresVal
        ))

        ++ (lib.lists.concatLists (map (feat: feat.layers or [ ]) featuresVal))

        ++ (lib.lists.concatLists (
          map (
            feat:
            let
              packages = (feat.libraries or [ ]) ++ (feat.executables or [ ]);
            in
            if builtins.length packages == 0 then
              [ ]
            else if feat.layered or false then
              (map (package: {
                name = "feat:${feat.name or "unknown"}:${package.name}";
                deps = [ package ];
              }) packages)
            else
              [
                {
                  name = "feat:${feat.name or "unknown"}";
                  deps = packages;
                }
              ]
          ) featuresVal
        ))

        ++ (lib.lists.concatLists (
          map (
            feat:
            let
              packages = feat.extensions or [ ];
            in
            if builtins.length packages == 0 then
              [ ]
            else if feat.layered or false then
              (map (package: {
                name = "feat:${feat.name or "unknown"}:${package.name}";
                deps = [ package ];
              }) packages)
            else
              [
                {
                  name = "feat:${feat.name or "unknown"}";
                  deps = packages;
                }
              ]
          ) featuresVal
        ))

        ++ (lib.lists.concatLists (
          map (
            feat:
            let
              mkExtProfilePkg =
                profileName: extensions:
                pkgs.runCommand profileName
                  {
                    allowSubstitutes = false;
                    preferLocalBuild = true;
                  }
                  ''
                    mkdir -p $out/etc/profile.d

                    ln -s ${
                      mkProfileScript profileName true ''
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
              packages = feat.extensions or [ ];
            in
            if builtins.length packages == 0 then
              [ ]
            else if feat.layered or false then
              (map (package: {
                name = "feat:${feat.name or "unknown"}:ext:${package.name}";
                paths = [
                  (mkExtProfilePkg "feat:${feat.name or "unknown"}:ext:${package.name}" [ package ])
                ];
                pathsToLink = [ "/etc/profile.d" ];
              }) packages)
            else
              [
                {
                  name = "feat:${feat.name or "unknown"}:ext";
                  paths = [
                    (mkExtProfilePkg "feat:${feat.name or "unknown"}:ext" packages)
                  ];
                  pathsToLink = [ "/etc/profile.d" ];
                }
              ]
          ) featuresVal
        ))

        ++ (map
          (
            feat:
            let
              profileNamePrefix = "feat:${feat.name or "unknown"}:onLogin";
              profilePkg =
                pkgs.runCommand profileNamePrefix
                  {
                    allowSubstitutes = false;
                    preferLocalBuild = true;
                  }
                  ''
                    mkdir -p $out/etc/profile.d

                    ln -s ${pkgs.writeScript "${profileNamePrefix}" ''
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

      ;

    in
    builtins.foldl' (
      layersList: el:
      let
        layer = pkgs.nix2container.buildLayer (
          {
            metadata = {
              author = el.name;
              created_by = el.name;
              comment = el.name;
            };
            layers = layersList;
            deps = el.deps or [ ];
            copyToRoot = el.copyToRoot or null;
            perms = el.perms or [ ];
            ignore = el.ignore or null;
          }
          // (lib.optionalAttrs (builtins.hasAttr "paths" el) {
            copyToRoot = pkgs.buildEnv {
              inherit (el) name paths pathsToLink;
            };
          })
        );
      in
      layersList ++ [ layer ]
    ) [ ] layersList;
}
