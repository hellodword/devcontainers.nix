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
      url = "github:nlewo/nix2container/b1579412e48c7e187bc23d4779de75d83c3a6bbb";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
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
      let
        lib = import ./lib;
        withNix = true;
        commonFeats = import ./lib/flake/common-features.nix {
          inherit (nixpkgs) lib;
          inherit withNix;
          features = lib.features;
        };
      in
      {
        imports = [ ];
        systems = [
          "x86_64-linux"
          # "aarch64-linux"
        ];

        flake = {
          inherit lib;

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

          let
          in
          {
            _module.args.pkgs = import ./lib/flake/mkPkgs.nix {
              inherit inputs nixpkgs system;
            };

            apps = import ./lib/flake/apps.nix {
              inherit pkgs nixpkgs self';
            };

            packages = import ./lib/flake/packages.nix {
              inherit
                self
                pkgs
                withNix
                commonFeats
                ;
            };

          };
      }
    );
}
