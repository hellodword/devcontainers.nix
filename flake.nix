{
  description = "Nixified devcontainers images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # nix-vscode-extensions = {
    #   url = "github:nix-community/nix-vscode-extensions";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      ...
    }:

    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        # config,
        # withSystem,
        # moduleWithSystem,
        ...
      }:
      {
        imports = [ ];
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];

        flake = {
          lib = import ./lib;
        };

        perSystem =
          {
            # self',
            # inputs',
            pkgs,
            system,
            # config,
            # lib,
            ...
          }:

          let
            overrides = pkgs.lib.mergeAttrsList (
              pkgs.lib.optional (builtins.pathExists ./overrides.nix) (import ./overrides.nix { inherit pkgs; })
            );

            # hello =
            #   let
            #     fromImageSha256 = {
            #       "x86_64-linux" = "sha256-2Pf/eU9h9Ol6we9YjfYdTUQvjgd/7N7Tt5Mc1iOPkLU=";
            #       "aarch64-linux" = "sha256-C75i+GJkPUN+Z+XSWHtunblM4l0kr7aT30Dqd0jjSTw=";
            #     };
            #   in
            #   self.lib.mkDevcontainer (
            #     {
            #       inherit pkgs;
            #       name = "hello";
            #       fromImage = pkgs.dockerTools.pullImage {
            #         imageName = "mcr.microsoft.com/devcontainers/base";
            #         imageDigest = "sha256:6155a486f236fd5127b76af33086029d64f64cf49dd504accb6e5f949098eb7e";
            #         sha256 = fromImageSha256.${system};
            #       };
            #       paths =
            #         with pkgs;
            #         [
            #           nixfmt-rfc-style
            #           nixd

            #           bash
            #           coreutils
            #           git

            #           curl
            #         ]
            #         ++ overrides.paths or [ ];
            #       extensions = with pkgs.vscode-extensions; [
            #         esbenp.prettier-vscode
            #         jnoortheen.nix-ide
            #       ];
            #       envVars = {
            #         FOO = "hello";
            #       };
            #     }
            #     // pkgs.lib.filterAttrs (n: _: n != "paths") overrides
            #   );

            go = self.lib.mkLayeredDevcontainer (
              {
                inherit pkgs;
                name = "go";
                packages =
                  with pkgs;
                  [
                    pkgs.go
                    delve
                    gotools
                    gopls
                    go-outline
                    gopkgs
                    gomodifytags
                    impl
                    gotests
                    go-tools # installing staticcheck (technically available in golangci-lint, but for use in lsp)
                    golangci-lint

                    k6
                  ]
                  ++ overrides.paths or [ ];
                extensions = with pkgs.vscode-extensions; [
                  esbenp.prettier-vscode
                  golang.go
                ];
                envVars = {
                  GOTOOLCHAIN = "local";
                };
                vscodeSettings = {
                  "go.toolsManagement.checkForUpdates" = "off";
                  "go.toolsManagement.autoUpdate" = false;
                  "go.logging.level" = "verbose";
                };
              }
              // pkgs.lib.filterAttrs (n: _: n != "paths") overrides
            );
          in
          rec {
            # define the overlay to be used for pkgs in our PerSystem function
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
              };

              overlays = [
                # inputs.nix-vscode-extensions.overlays.default
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
                          ${
                            if builtins.match ".+\.tar\.gz$" packages.${x}.meta.name == null then
                              "nix build .#${x} && ./result | docker image load"
                            else
                              "nix build .#${x} && docker load < result"
                          }
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
              # inherit hello;
              inherit go;
            };
          };
      }
    );
}
