{
  description = "Nixified devcontainers images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:

    flake-parts.lib.mkFlake { inherit inputs; } (
      top@{
        config,
        withSystem,
        moduleWithSystem,
        ...
      }:
      {
        imports = [ ];
        systems = [ "x86_64-linux" ];

        flake = {
          # https://github.com/niksi-aalto/niksi-devcontainer
          lib.mkDevcontainer =
            {
              pkgs,
              name,
              tag ? "latest",
              fromImage ? pkgs.dockerTools.pullImage {
                imageName = "mcr.microsoft.com/devcontainers/base";
                imageDigest = "sha256:6155a486f236fd5127b76af33086029d64f64cf49dd504accb6e5f949098eb7e";
                sha256 = "sha256-2Pf/eU9h9Ol6we9YjfYdTUQvjgd/7N7Tt5Mc1iOPkLU=";
              },
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
            };

          lib.mkLayeredDevcontainer =
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
            pkgs.dockerTools.buildLayeredImage {
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
            };
        };

        perSystem =
          {
            self',
            inputs',
            pkgs,
            system,
            config,
            lib,
            ...
          }:

          let
            overrides = pkgs.lib.mergeAttrsList (
              pkgs.lib.optional (builtins.pathExists ./overrides.nix) (import ./overrides.nix { inherit pkgs; })
            );
          in
          rec {
            # define the overlay to be used for pkgs in our PerSystem function
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
              };

              overlays = with inputs; [
                nix-vscode-extensions.overlays.default
              ];
            };

            apps =
              (builtins.listToAttrs (
                map (x: {
                  name = "${x}";
                  value =
                    let
                      program = pkgs.writeShellApplication {
                        name = "exe";
                        text = ''
                          nix build .#${x} && docker load < result
                        '';
                      };
                    in
                    {
                      type = "app";
                      program = "${nixpkgs.lib.getExe program}";
                    };
                }) (builtins.attrNames packages)
              ))
              // {
                all =
                  let
                    program = pkgs.writeShellApplication {
                      name = "exe";
                      text = ''
                        ${builtins.concatStringsSep "\n" (
                          map (x: "nix build .#${x} && docker load < result") (builtins.attrNames packages)
                        )}
                      '';
                    };
                  in
                  {
                    type = "app";
                    program = "${nixpkgs.lib.getExe program}";
                  };
              };

            packages = {
              hello = self.lib.mkDevcontainer (
                {
                  inherit pkgs;
                  name = "hello";
                  paths =
                    with pkgs;
                    [
                      nixfmt-rfc-style
                      nixd

                      bash
                      coreutils
                      git

                      curl
                    ]
                    ++ overrides.paths or [ ];
                  extensions =
                    (with pkgs.vscode-extensions; [
                      esbenp.prettier-vscode
                    ])
                    ++ (with pkgs.vscode-marketplace; [
                      jnoortheen.nix-ide
                    ]);
                  envVars = {
                    FOO = "hello";
                  };
                }
                // pkgs.lib.filterAttrs (n: _: n != "paths") overrides
              );

              hello-layered = self.lib.mkLayeredDevcontainer (
                {
                  inherit pkgs;
                  name = "hello-layered";
                  packages =
                    with pkgs;
                    [
                      git

                      curl
                    ]
                    ++ overrides.paths or [ ];
                  extensions =
                    (with pkgs.vscode-extensions; [
                      esbenp.prettier-vscode
                    ])
                    ++ (with pkgs.vscode-marketplace; [ ]);
                  envVars = {
                    FOO = "hello";
                  };
                }
                // pkgs.lib.filterAttrs (n: _: n != "paths") overrides
              );

            };
          };
      }
    );
}
