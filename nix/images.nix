# Single mkDevcontainerImage constructor building dev (:latest), agent (:agent), and shared OCI layout.
{
  self,
  pkgs,
  lib,
  inputs,
  system,
  cache,
}:
let
  inherit (pkgs) nix2container;
  runtime = import ../runtime { inherit pkgs lib; };
  foundation = import ./foundation.nix {
    inherit
      pkgs
      lib
      inputs
      cache
      runtime
      ;
  };
  agents = import ./agents.nix { inherit inputs system; };
  editor = import ./editor.nix { inherit pkgs lib; };

  toolchainModules = [
    (import ./toolchains/c.nix { inherit pkgs; })
    (import ./toolchains/rust.nix { inherit pkgs; })
    (import ./toolchains/go.nix { inherit pkgs; })
    (import ./toolchains/python.nix { inherit pkgs; })
    (import ./toolchains/nodejs.nix { inherit pkgs; })
    (import ./toolchains/nix-lang.nix { inherit pkgs; })
    (import ./toolchains/formats.nix { inherit pkgs; })
  ];

  rustToolchain = (import ./toolchains/rust.nix { inherit pkgs; }).rustToolchain;
  nodejsToolchain = import ./toolchains/nodejs.nix { inherit pkgs; };

  toolchainsUsrPackages = lib.concatMap (m: m.usrPackages) toolchainModules;
  toolchainsStoreDeps = lib.unique (
    lib.concatMap (m: m.storeDeps) toolchainModules
    ++ [
      inputs.nixpkgs.outPath
      inputs.rust-overlay.outPath
    ]
  );
  toolchainsPathSegments = lib.concatMap (m: m.pathSegments) toolchainModules;
  toolchainsEnv = lib.foldl' (acc: m: acc // m.env) { } toolchainModules;

  layers = import ./layers.nix {
    inherit
      pkgs
      nix2container
      foundation
      toolchainsStoreDeps
      agents
      editor
      runtime
      ;
  };

  revision =
    if self ? rev then
      self.rev
    else if self ? dirtyRev then
      self.dirtyRev
    else
      "dirty";
  dirty = !(self ? rev);
  version = if self ? shortRev then self.shortRev else "dev";

  baseLabels = {
    "org.opencontainers.image.revision" = revision;
    "org.opencontainers.image.version" = version;
    "devcontainers.nix.revision" = revision;
    "devcontainers.nix.version" = version;
    "devcontainers.nix.dirty" = if dirty then "true" else "false";
  };

  usrMergePostBuild = ''
    merge_usr_dir() {
      local src="$1"
      local dst="$2"
      mkdir -p "$out/$dst"
      if [ -e "$out/$src" ] && [ ! -L "$out/$src" ]; then
        cp -a "$out/$src"/. "$out/$dst"/
        rm -rf "$out/$src"
      elif [ -L "$out/$src" ]; then
        rm "$out/$src"
      fi
      ln -s "$dst" "$out/$src"
    }

    mkdir -p \
      "$out/usr/bin" \
      "$out/usr/sbin" \
      "$out/usr/lib" \
      "$out/usr/lib64" \
      "$out/usr/libexec" \
      "$out/usr/include" \
      "$out/usr/share" \
      "$out/usr/local/bin" \
      "$out/usr/local/etc" \
      "$out/usr/local/include" \
      "$out/usr/local/lib" \
      "$out/usr/local/lib64" \
      "$out/usr/local/sbin" \
      "$out/usr/local/share" \
      "$out/usr/local/src"

    merge_usr_dir bin usr/bin
    merge_usr_dir sbin usr/sbin
    merge_usr_dir lib usr/lib
    merge_usr_dir lib64 usr/lib64
    merge_usr_dir libexec usr/libexec
    merge_usr_dir include usr/include
    merge_usr_dir share usr/share
  '';

  devPathSegments = [
    "/home/vscode/.local/share/devcontainer/bin"
    "/home/vscode/.local/share/nix-profile/bin"
    "/home/vscode/.nix-profile/bin"
  ]
  ++ toolchainsPathSegments
  ++ [
    "/usr/local/bin"
    "/usr/bin"
  ];

  mkDevcontainerImage =
    {
      variantName,
      tag,
      imageLayers,
      includeToolchainsInUsr,
      includeEditor,
    }:
    let
      pathSegments = if includeToolchainsInUsr then devPathSegments else foundation.agentPathSegments;
      envWithoutPath = foundation.baseEnv // (if includeToolchainsInUsr then toolchainsEnv else { });
      fullEnv = envWithoutPath // {
        PATH = lib.concatStringsSep ":" pathSegments;
      };
      shellFiles = foundation.mkShellFiles {
        envAttrs = envWithoutPath;
        inherit pathSegments;
      };

      usrPaths =
        foundation.usrPackages
        ++ agents.allPackages
        ++ lib.optionals includeToolchainsInUsr toolchainsUsrPackages
        ++ lib.optionals includeEditor runtime.editorHelpers;

      usrRoot = pkgs.buildEnv {
        name = "devcontainer-${variantName}-usr";
        paths = usrPaths;
        pathsToLink = [
          "/bin"
          "/sbin"
          "/lib"
          "/lib64"
          "/libexec"
          "/include"
          "/share"
        ];
        ignoreCollisions = true;
        postBuild =
          usrMergePostBuild
          + ''
            mkdir -p "$out/usr/share/devcontainer"
            ln -sfn ${inputs.nixpkgs.outPath} "$out/usr/share/devcontainer/nixpkgs"
            ln -sfn ${inputs.rust-overlay.outPath} "$out/usr/share/devcontainer/rust-overlay"
          ''
          + lib.concatMapStringsSep "\n" (link: ''
            mkdir -p "$out$(dirname ${lib.escapeShellArg link.target})"
            ln -sfn ${lib.escapeShellArg link.source} "$out${link.target}"
          '') foundation.fhsSymlinks
          + lib.optionalString includeToolchainsInUsr ''
            if [ ! -e "$out/usr/lib/node_modules/typescript/lib" ]; then
              mkdir -p "$out/usr/lib/node_modules/typescript"
              ln -sfn ${nodejsToolchain.typescriptPkg}/lib/typescript "$out/usr/lib/node_modules/typescript/lib"
            fi
          ''
          + lib.optionalString includeEditor ''
            mkdir -p "$out/usr/share/devcontainer/vscode"
            printf '%s\n' ${lib.escapeShellArg editor.tasksJson} > "$out/usr/share/devcontainer/tasks.json"
            printf '%s\n' ${lib.escapeShellArg editor.extensionsIndexJson} > "$out/usr/share/devcontainer/vscode/extensions-index.json"
          '';
      };

      passwdText = ''
        root:x:0:0:root:/root:/bin/bash
        vscode:x:1000:1000:vscode:/home/vscode:/bin/bash
        nobody:x:65534:65534:nobody:/var/empty:/usr/bin/nologin
      '';
      groupText = ''
        root:x:0:
        vscode:x:1000:vscode
        nogroup:x:65534:
      '';
      shadowText = ''
        root:!:1::::::
        vscode:!:1::::::
        nobody:!:1::::::
      '';
      nsswitchText = ''
        passwd: files
        group: files
        shadow: files
        hosts: files dns
        networks: files
        protocols: files
        services: files
      '';
      shellsText = ''
        /bin/sh
        /bin/bash
        /usr/bin/sh
        /usr/bin/bash
      '';
      osReleaseText = ''
        NAME="devcontainer-nix"
        ID=devcontainer-nix
        VERSION_ID="26.11"
        PRETTY_NAME="Devcontainer Nix"
      '';
      gitconfigText = ''
        [filter "lfs"]
        	clean = git-lfs clean -- %f
        	smudge = git-lfs smudge -- %f
        	process = git-lfs filter-process
        	required = true
      '';
      sshConfigText = ''
        Host *
          GlobalKnownHostsFile /etc/ssh/ssh_known_hosts
      '';
      nixpkgsConfigText = ''
        {
          allowUnfree = true;
          android_sdk.accept_license = true;
          oraclejdk.accept_license = true;
          allowUnsupportedSystem = true;
        }
      '';
      userBashrcText = ''
        if [ -r /etc/bashrc ]; then
          . /etc/bashrc
        fi
      '';

      directories = {
        "/root" = {
          mode = "0700";
          uid = 0;
          gid = 0;
        };
        "/home" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/home/vscode" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.config" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.cache" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.local" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.local/share" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.local/state" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.local/state/bash" = {
          mode = "0700";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.local/state/devcontainer" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/home/vscode/.codex" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/tmp" = {
          mode = "1777";
          uid = 0;
          gid = 0;
        };
        "/var" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/var/empty" = {
          mode = "0555";
          uid = 0;
          gid = 0;
        };
        "/var/cache" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/var/lib" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/var/lib/devcontainer" = {
          mode = "0755";
          uid = 1000;
          gid = 1000;
        };
        "/var/lib/dbus" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/var/log" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/var/tmp" = {
          mode = "1777";
          uid = 0;
          gid = 0;
        };
        "/run" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/run/user" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
        "/run/user/1000" = {
          mode = "0700";
          uid = 1000;
          gid = 1000;
        };
        "/workspaces" = {
          mode = "0777";
          uid = 0;
          gid = 0;
        };
        "/etc/xdg" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
      };

      filesystemRoot = pkgs.runCommand "devcontainer-${variantName}-filesystem" { } (
        ''
          mkdir -p \
            "$out/etc/profile.d" \
            "$out/etc/nixpkgs" \
            "$out/etc/nix" \
            "$out/etc/ssh" \
            "$out/etc/ssl/certs" \
            "$out/etc/dbus-1"
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (path: spec: ''
              mkdir -p "$out${path}"
              chmod ${spec.mode} "$out${path}"
            '') directories
          )}

          ln -sfn /run "$out/var/run"
          ln -sfn /var/lib/devcontainer/machine-id "$out/etc/machine-id"
          ln -sfn /etc/machine-id "$out/var/lib/dbus/machine-id"
          touch "$out/var/lib/devcontainer/machine-id"
          chmod 0444 "$out/var/lib/devcontainer/machine-id"

          ln -sfn ${pkgs.iana-etc}/etc/services "$out/etc/services"
          ln -sfn ${pkgs.iana-etc}/etc/protocols "$out/etc/protocols"
          ln -sfn ${pkgs.mailcap}/etc/mime.types "$out/etc/mime.types"
          ln -sfn ${pkgs.tzdata}/share/zoneinfo "$out/etc/zoneinfo"
          ln -sfn /etc/zoneinfo/UTC "$out/etc/localtime"
          ln -sfn ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "$out/etc/ssl/certs/ca-certificates.crt"
          ln -sfn ${pkgs.dbus}/share/dbus-1/session.conf "$out/etc/dbus-1/session.conf"

          cp -a --no-preserve=mode,ownership ${foundation.fontsRoot}/. "$out/"
          chmod -R u+w "$out/etc"

          printf '%s' ${lib.escapeShellArg passwdText} > "$out/etc/passwd"
          printf '%s' ${lib.escapeShellArg groupText} > "$out/etc/group"
          printf '%s' ${lib.escapeShellArg shadowText} > "$out/etc/shadow"
          printf '%s' ${lib.escapeShellArg nsswitchText} > "$out/etc/nsswitch.conf"
          printf '%s' ${lib.escapeShellArg shellsText} > "$out/etc/shells"
          printf '%s' ${lib.escapeShellArg osReleaseText} > "$out/etc/os-release"
          printf '%s' ${lib.escapeShellArg gitconfigText} > "$out/etc/gitconfig"
          printf '%s' ${lib.escapeShellArg sshConfigText} > "$out/etc/ssh/ssh_config"
          : > "$out/etc/ssh/ssh_known_hosts"
          printf '%s' ${lib.escapeShellArg nixpkgsConfigText} > "$out/etc/nixpkgs/config.nix"
          printf '%s' ${lib.escapeShellArg foundation.nixDaemonConf} > "$out/etc/nix/nix.conf"
          printf '%s' ${lib.escapeShellArg shellFiles.profileText} > "$out/etc/profile"
          printf '%s' ${lib.escapeShellArg shellFiles.bashrcText} > "$out/etc/bashrc"
          printf '%s' ${lib.escapeShellArg shellFiles.bashBashrcText} > "$out/etc/bash.bashrc"
          printf '%s' ${lib.escapeShellArg userBashrcText} > "$out/home/vscode/.bashrc"

          chmod 0644 \
            "$out/etc/passwd" \
            "$out/etc/group" \
            "$out/etc/nsswitch.conf" \
            "$out/etc/shells" \
            "$out/etc/os-release" \
            "$out/etc/gitconfig" \
            "$out/etc/ssh/ssh_config" \
            "$out/etc/ssh/ssh_known_hosts" \
            "$out/etc/nixpkgs/config.nix" \
            "$out/etc/nix/nix.conf" \
            "$out/etc/profile" \
            "$out/etc/bashrc" \
            "$out/etc/bash.bashrc" \
            "$out/home/vscode/.bashrc"
          chmod 0640 "$out/etc/shadow"
        ''
        + lib.optionalString includeEditor (
          lib.concatMapStringsSep "\n" (root: ''
            mkdir -p "$out${root}/data/Machine"
            chmod 0755 "$out${root}" "$out${root}/data" "$out${root}/data/Machine"
            printf '%s' ${lib.escapeShellArg editor.machineSettingsJson} > "$out${root}/data/Machine/settings.json"
            chmod 0444 "$out${root}/data/Machine/settings.json"
          '') editor.serverRoots
        )
      );

      unameFor = uid: if uid == 0 then "root" else "vscode";
      gnameFor = gid: if gid == 0 then "root" else "vscode";

      dirPerms = lib.mapAttrsToList (path: spec: {
        path = filesystemRoot;
        regex = "^${filesystemRoot}${path}$";
        inherit (spec) mode uid gid;
        uname = unameFor spec.uid;
        gname = gnameFor spec.gid;
      }) directories;

      filePerms = [
        {
          path = filesystemRoot;
          regex = "^${filesystemRoot}/var/lib/devcontainer/machine-id$";
          mode = "0444";
          uid = 1000;
          gid = 1000;
          uname = "vscode";
          gname = "vscode";
        }
        {
          path = filesystemRoot;
          regex = "^${filesystemRoot}/home/vscode/\\.bashrc$";
          mode = "0644";
          uid = 1000;
          gid = 1000;
          uname = "vscode";
          gname = "vscode";
        }
        {
          path = filesystemRoot;
          regex = "^${filesystemRoot}/etc/shadow$";
          mode = "0640";
          uid = 0;
          gid = 0;
          uname = "root";
          gname = "root";
        }
      ]
      ++ lib.optionals includeEditor (
        lib.concatMap (root: [
          {
            path = filesystemRoot;
            regex = "^${filesystemRoot}${root}(/data(/Machine)?)?$";
            mode = "0755";
            uid = 1000;
            gid = 1000;
            uname = "vscode";
            gname = "vscode";
          }
          {
            path = filesystemRoot;
            regex = "^${filesystemRoot}${root}/data/Machine/settings\\.json$";
            mode = "0444";
            uid = 0;
            gid = 0;
            uname = "root";
            gname = "root";
          }
        ]) editor.serverRoots
      );

      labels =
        baseLabels
        // lib.optionalAttrs includeEditor {
          "devcontainer.metadata" = builtins.toJSON editor.devcontainerMetadata;
        };

      imageConfig = {
        User = "vscode";
        WorkingDir = "/workspaces";
        Env = lib.mapAttrsToList (name: value: "${name}=${value}") fullEnv;
        Entrypoint = [ "/usr/bin/devcontainer-entrypoint" ];
        Cmd = [ "/bin/bash" ];
        Labels = labels;
      };

      configFile = pkgs.writeText "devcontainer-${variantName}-config.json" (builtins.toJSON imageConfig);

      excludedGraphRootsJson = builtins.toJSON (
        map toString (
          [
            configFile
            usrRoot
            filesystemRoot
          ]
          ++ imageLayers
        )
      );

      closureGraphJson =
        pkgs.runCommand "devcontainer-${variantName}-closure-graph.json"
          {
            __structuredAttrs = true;
            exportReferencesGraph.graph = [
              configFile
              usrRoot
              filesystemRoot
            ]
            ++ imageLayers;
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            excluded=${lib.escapeShellArg excludedGraphRootsJson}
            jq --argjson excluded "$excluded" '
              .graph
              | map(select((.path as $p | ($excluded | index($p))) == null) | .references |= sort)
              | sort_by(.path)
            ' .attrs.json > "$out"
          '';

      nixDatabase =
        pkgs.runCommand "devcontainer-${variantName}-nix-database"
          {
            nativeBuildInputs = [
              pkgs.jq
              pkgs.nix
              pkgs.sqlite
            ];
          }
          ''
            jq -r 'map([.path, .narHash, .narSize, "", (.references | length)] + .references) | add | map("\(.)\n") | add' ${closureGraphJson} \
              | head -n -1 \
              | NIX_REMOTE="local?root=$PWD" nix-store --load-db -j 1

            sqlite3 "$PWD/nix/var/nix/db/db.sqlite" 'UPDATE ValidPaths SET registrationTime = 0'
            sqlite3 "$PWD/nix/var/nix/db/db.sqlite" '.dump' > db.dump
            mkdir -p "$out/nix/var/nix/db"
            sqlite3 "$out/nix/var/nix/db/db.sqlite" '.read db.dump'
            cp "$PWD/nix/var/nix/db/schema" "$out/nix/var/nix/db/schema"
            sqlite3 "$out/nix/var/nix/db/db.sqlite" 'pragma journal_mode = wal' > /dev/null

            mkdir -p "$out/nix/var/nix/gcroots/docker"
            # shellcheck disable=SC2046
            ln -s $(jq -r '.[].path' ${closureGraphJson}) "$out/nix/var/nix/gcroots/docker/"
            mkdir -p "$out/nix/store/.links"
          '';

      explicitPermsJson = builtins.toJSON (
        dirPerms
        ++ filePerms
        ++ [
          {
            path = "${nixDatabase}";
            regex = ".*";
            mode = "0755";
            uid = 1000;
            gid = 1000;
            uname = "vscode";
            gname = "vscode";
          }
        ]
      );

      customPermsFile =
        pkgs.runCommand "devcontainer-${variantName}-top-perms.json"
          {
            __structuredAttrs = true;
            exportReferencesGraph.graph = [
              usrRoot
              filesystemRoot
              nixDatabase
            ];
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            explicit=${lib.escapeShellArg explicitPermsJson}
            roots=${
              lib.escapeShellArg (
                builtins.toJSON [
                  "${usrRoot}"
                  "${filesystemRoot}"
                  "${nixDatabase}"
                ]
              )
            }
            jq --argjson explicit "$explicit" --argjson roots "$roots" '
              $explicit + [
                .graph[].path
                | select((. as $p | ($roots | index($p))) == null)
                | {
                    path: .,
                    regex: ".*",
                    mode: "",
                    uid: 1000,
                    gid: 1000,
                    uname: "vscode",
                    gname: "vscode"
                  }
              ]
            ' .attrs.json > "$out"
          '';

      customizationLayer =
        (nix2container.buildLayer {
          maxLayers = 1;
          permsFile = customPermsFile;
          copyToRoot = [
            usrRoot
            filesystemRoot
            nixDatabase
          ];
          deps = [ configFile ];
          ignore = configFile;
          layers = imageLayers;
          metadata.created_by = "devcontainers.nix top layer ${variantName}";
        })
        // {
          nestedLayers = [ ];
        };

      allImageLayers = imageLayers ++ [ customizationLayer ];
    in
    pkgs.runCommandLocal "image-devcontainers-dev.json"
      {
        passthru = {
          imageName = "ghcr.io/hellodword/devcontainers-dev";
          imageTag = tag;
        };
      }
      ''
        ${pkgs.nix2container-bin}/bin/nix2container image \
          "$out" \
          --arch amd64 \
          --created 0001-01-01T00:00:00Z \
          ${configFile} \
          ${lib.concatMapStringsSep " " (layer: "${layer}/layers.json") allImageLayers}
      '';

  dev = mkDevcontainerImage {
    variantName = "dev";
    tag = "latest";
    imageLayers = layers.devLayers;
    includeToolchainsInUsr = true;
    includeEditor = true;
  };

  agent = mkDevcontainerImage {
    variantName = "agent";
    tag = "agent";
    imageLayers = layers.sharedLayers;
    includeToolchainsInUsr = false;
    includeEditor = false;
  };

  oci =
    pkgs.runCommand "devcontainers-dev-oci"
      {
        nativeBuildInputs = [
          pkgs.skopeo-nix2container
          pkgs.python3
        ];
      }
      ''
        tmpdir="$TMPDIR/skopeo"
        mkdir -p "$tmpdir" "$out"
        skopeo --tmpdir "$tmpdir" --insecure-policy copy \
          nix:${dev} "oci:$out:latest"
        skopeo --tmpdir "$tmpdir" --insecure-policy copy \
          nix:${agent} "oci:$out:agent"
        python3 ${../tests/check_oci_layout.py} "$out"
      '';
in
{
  inherit
    dev
    agent
    oci
    runtime
    foundation
    agents
    editor
    rustToolchain
    toolchainsUsrPackages
    toolchainsStoreDeps
    ;
}
