{
  description = "Nixified devcontainers images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
            self',
            # inputs',
            pkgs,
            system,
            # config,
            # lib,
            ...
          }:

          {
            # define the overlay to be used for pkgs in our PerSystem function
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
              };

              overlays = [
                inputs.nix-vscode-extensions.overlays.default
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
                          if builtins.hasAttr "copyToDockerDaemon" self'.packages.${x} then
                            "nix run .#${x}.copyToDockerDaemon"
                          else if builtins.match ".+\.tar\.gz$" (self'.packages.${x}.meta.name or "") == null then
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
              }) (builtins.attrNames self'.packages)
            );

            packages = {

              devcontainers-base = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-base";
              };

              devcontainers-dev = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-dev";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                ];
              };

              devcontainers-nix = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-nix";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  nix
                ];
              };

              devcontainers-go = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-go";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  go
                  node
                ];
              };

              devcontainers-cpp = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-cpp";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  cpp
                ];
              };

              devcontainers-vala = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-vala";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  vala
                ];
              };

              devcontainers-dotnet = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-dotnet";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  dotnet
                ];
              };

              devcontainers-node = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-node";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  node
                ];
              };

            };
          };
      }
    );
}
