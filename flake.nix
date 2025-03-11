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
            };
          };
      }
    );
}
