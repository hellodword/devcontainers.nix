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
      inputs.oranc.follows = "core/oranc";
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
              nix2container-bin
              skopeo-nix2container
              ;
          })
          rust-overlay.overlays.default
          nix-index-database.overlays.nix-index
        ];
      };
      inherit (pkgs) lib;
      cache = import ./nix/cache.nix { inherit core lib; };
      images = import ./nix/images.nix {
        inherit
          self
          pkgs
          lib
          inputs
          system
          cache
          ;
      };
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      loadAppPkg = pkgs.writeShellApplication {
        name = "load-devcontainer-image";
        runtimeInputs = [
          pkgs.docker-client
          pkgs.jq
          pkgs.skopeo-nix2container
        ];
        text = ''
          export OCI_DIR=${lib.escapeShellArg "${images.oci}"}
          exec ${pkgs.bash}/bin/bash ${./scripts/load-image.sh} "$@"
        '';
      };

      verifyAppPkg = pkgs.writeShellApplication {
        name = "verify-devcontainers";
        runtimeInputs = [
          core.packages.${system}.ci-tools
          core.packages.${system}.oranc
          agents-misc.packages.${system}.vm-test-submit
          pkgs.actionlint
          pkgs.distribution
          pkgs.git
          pkgs.jq
          pkgs.nix
          pkgs.python3
          pkgs.ruff
          pkgs.shellcheck
          pkgs.skopeo-nix2container
          pkgs.zstd
        ];
        text = ''
          exec ${pkgs.python3}/bin/python3 ${./tests/verify.py} "$@"
        '';
      };
    in
    {
      formatter.${system} = treefmtEval.config.build.wrapper;

      packages.${system} = {
        inherit (images) dev agent oci;
        default = images.oci;
      };

      apps.${system} = rec {
        load = {
          type = "app";
          program = "${loadAppPkg}/bin/load-devcontainer-image";
          meta.description = "Load the latest or agent variant into the local Docker daemon";
        };
        verify = {
          type = "app";
          program = "${verifyAppPkg}/bin/verify-devcontainers";
          meta.description = "Run static checks, OCI layout validation, release tests, and VM acceptance suites";
        };
        default = load;
      };

      checks.${system} = {
        formatting = treefmtEval.config.build.check self;
        lint = import ./nix/lint.nix {
          inherit
            self
            pkgs
            lib
            images
            ;
        };
        vm-containers = import ./tests/vm/containers.nix {
          inherit
            pkgs
            core
            inputs
            images
            ;
        };
        vm-editor = import ./tests/vm/editor.nix {
          inherit
            pkgs
            core
            images
            ;
        };
      };

      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [
          core.packages.${system}.ci-tools
          core.packages.${system}.oranc
          agents-misc.packages.${system}.vm-test-submit
          pkgs.actionlint
          pkgs.distribution
          pkgs.gh
          pkgs.git
          pkgs.jq
          pkgs.nix.out
          pkgs.nixfmt
          pkgs.prettier
          pkgs.python3
          pkgs.ruff
          pkgs.shellcheck
          pkgs.shfmt
          pkgs.skopeo
          pkgs.zstd
        ];
      };

      lib.${system} = {
        inherit cache images pkgs;
      };
    };
}
