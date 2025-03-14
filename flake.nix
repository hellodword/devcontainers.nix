{
  description = "Nixified devcontainers images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # nix-vscode-extensions = {
    #   url = "github:nix-community/nix-vscode-extensions";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    nix2container = {
      url = "github:nlewo/nix2container";
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

            devcontainers-go = self.lib.mkManuallyLayeredDevcontainer {
              inherit pkgs;
              name = "devcontainers-go";
              packages = with pkgs; [
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
              ];
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
                "json.format.enable" = false;
                "[json]" = {
                  "editor.defaultFormatter" = "esbenp.prettier-vscode";
                };
                "[jsonc]" = {
                  "editor.defaultFormatter" = "esbenp.prettier-vscode";
                };
                "[markdown]" = {
                  "editor.defaultFormatter" = "esbenp.prettier-vscode";
                };
                "prettier.enable" = true;
              };
              metadata = {
                # https://github.com/devcontainers/features/blob/c264b4e837f3273789fc83dae898152daae4cd90/src/go/devcontainer-feature.json#L38-L43
                "capAdd" = [
                  "SYS_PTRACE"
                ];
                "securityOpt" = [
                  "seccomp=unconfined"
                ];
              };
            };

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
                (prev: final: { inherit (inputs.nix2container.packages.${system}) nix2container; })
              ];
            };

            apps = builtins.listToAttrs (
              map (x: {
                name = "${x}";
                value =
                  let
                    program = pkgs.writeShellApplication {
                      name = "exe";
                      text = ''
                        ${
                          if builtins.hasAttr "copyToDockerDaemon" packages.${x} then
                            "nix run .#${x}.copyToDockerDaemon"
                          else if builtins.match ".+\.tar\.gz$" (packages.${x}.meta.name or "") == null then
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
            );

            packages = {
              # inherit hello;
              inherit devcontainers-go;
            };
          };
      }
    );
}
