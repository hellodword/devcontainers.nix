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
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
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
            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              config = {
                allowUnfree = true;
                android_sdk.accept_license = true;
                oraclejdk.accept_license = true;

                # allowBroken = true;
                # allowUnsupportedSystem = true;
                # allowInsecurePredicate = (_: true);
              };

              overlays = [
                inputs.nix-vscode-extensions.overlays.default
                (prev: final: { inherit (inputs.nix2container.packages.${system}) nix2container; })
                inputs.rust-overlay.overlays.default
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

              base = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-base";
              };

              dev = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-dev";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                ];
              };

              nix = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-nix";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  nix
                ];
              };

              go = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-go";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  go
                ];
              };

              go-web = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-go";
                tag = "web";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  go
                  node
                ];
              };

              cpp = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-cpp";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  cpp
                ];
              };

              vala = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-vala";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  vala
                ];
              };

              dotnet = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-dotnet";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  dotnet
                ];
              };

              node = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-node";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  node
                ];
              };

              rust = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-rust";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  rust
                ];
              };

              python = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-python";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  python
                ];
              };

              java = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-java";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  java
                ];
              };

              php = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-php";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  php
                ];
              };

              php-web = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-php";
                tag = "web";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  php
                  node
                ];
              };

              haskell = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-haskell";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  haskell
                ];
              };

              dart = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-dart";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  dart
                ];
              };

              lua = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-lua";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  lua
                ];
              };

              zig = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "devcontainers-zig";
                features = with self.lib.features; [
                  dev0
                  dev1
                  dev2
                  zig
                ];
              };

            };
          };
      }
    );
}
