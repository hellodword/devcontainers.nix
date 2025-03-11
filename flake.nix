{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
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
              extProfile = pkgs.writeText "ext-profile" ''
                if [ -f /home/${username}/.vscode-server/extensions/extensions.json ]; then
                  exit 0
                fi

                mkdir -p /home/${username}/.vscode-server/extensions

                cat > /home/${username}/.vscode-server/extensions/extensions.json <<EOF
                ${builtins.toJSON extensionsJson}
                EOF

                chown -R ${username}:${username} /home/${username}
              '';
            in
            pkgs.dockerTools.buildImage {
              inherit name tag fromImage;
              diskSize = 1024 * 2;
              copyToRoot = pkgs.buildEnv {
                name = "env";
                paths =
                  paths
                  ++ [ pkgs.dockerTools.binSh ]
                  ++ [
                    (pkgs.runCommand "profile" { } ''
                      mkdir -p $out/etc/profile.d
                      cp ${envProfile} $out/etc/profile.d/10-env-profile.sh
                      cp ${extProfile} $out/etc/profile.d/11-ext-profile.sh
                    '')
                  ];
                pathsToLink = pathsToLink ++ [ "/etc/profile.d" ] ++ (map (x: "${x}") extensions);
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
          { config, pkgs, ... }:

          let
            overrides = pkgs.lib.mergeAttrsList (
              pkgs.lib.optional (builtins.pathExists ./overrides.nix) (import ./overrides.nix { inherit pkgs; })
            );
          in
          rec {
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
                      fh
                    ]
                    ++ overrides.paths or [ ];
                  extensions = with pkgs.vscode-extensions; [
                    jnoortheen.nix-ide
                    esbenp.prettier-vscode
                  ];
                  envVars = {
                    FOO = "hello";
                  };
                }
                // pkgs.lib.filterAttrs (n: _: n != "paths") overrides
              );
            };

            apps = builtins.listToAttrs (
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
            );

          };
      }
    );
}
