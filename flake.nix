{
  description = "Modular Nix/OCI development and agent container images";

  inputs = {
    core.url = "git+https://github.com/hellodword/nixos-config.git?ref=master&dir=infra";
    nixpkgs.follows = "core/nixpkgs";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents.url = "github:numtide/llm-agents.nix";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agents-misc = {
      url = "github:hellodword/agents-misc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      core,
      nixpkgs,
      rust-overlay,
      nix-vscode-extensions,
      nix-index-database,
      treefmt-nix,
      nix2container,
      agents-misc,
      ...
    }:
    let
      system = "x86_64-linux";
      nixpkgsConfig = {
        allowUnfree = true;
        android_sdk.accept_license = true;
        oraclejdk.accept_license = true;
        allowUnsupportedSystem = true;
      };
      pkgs = import nixpkgs {
        inherit system;
        config = nixpkgsConfig;
        overlays = [
          nix-vscode-extensions.overlays.default
          (final: prev: {
            inherit (nix2container.packages.${system})
              nix2container
              skopeo-nix2container
              ;
          })
          rust-overlay.overlays.default
          nix-index-database.overlays.nix-index
        ];
      };
      inherit (pkgs) lib;
      cache = import ./nix/cache.nix { inherit core lib; };
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
    in
    {
      formatter.${system} = treefmtEval.config.build.wrapper;

      checks.${system} = {
        formatting = treefmtEval.config.build.check self;
      };

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          core.packages.${system}.ci-tools
          core.packages.${system}.oranc
          agents-misc.packages.${system}.vm-test-submit
          pkgs.actionlint
          pkgs.jq
          pkgs.nixfmt
          pkgs.prettier
          pkgs.python3
          pkgs.ruff
          pkgs.shellcheck
          pkgs.shfmt
          pkgs.skopeo
        ];
      };

      lib.${system} = {
        inherit cache;
      };
    };
}
