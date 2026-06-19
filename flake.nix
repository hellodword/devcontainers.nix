{
  description = "Devcontainer Nix/OCI image compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

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

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
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
      rust-overlay,
      nix-vscode-extensions,
      nix2container,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ rust-overlay.overlays.default ];
      };
      lib = pkgs.lib;
      compiler = import ./lib {
        inherit
          self
          pkgs
          lib
          system
          inputs
          ;
      };
      imageModules = {
        nix = ./images/nix.nix;
        python = ./images/python.nix;
        nodejs = ./images/nodejs.nix;
        go = ./images/go.nix;
        rust = ./images/rust.nix;
        python-web = ./images/python-web.nix;
        go-web = ./images/go-web.nix;
        rust-web = ./images/rust-web.nix;
        flutter = ./images/flutter.nix;
      };
      imageNames = builtins.attrNames imageModules;
      images = lib.mapAttrs (_: module: compiler.mkImage { inherit module; }) imageModules;
      imageNameToCheckName = name: lib.replaceStrings [ "-" ] [ "_" ] name;
      imageLoadApps = lib.mapAttrs' (
        name: image:
        let
          loadImage = pkgs.writeShellApplication {
            name = "load-${name}";
            runtimeInputs = [
              pkgs.docker
              pkgs.jq
              nix2container.packages.${system}.skopeo-nix2container
            ];
            text = ''
              tmpdir="''${TMPDIR:-/tmp}"
              echo "Copy to Docker daemon image ${image.oci.imageName}:${image.oci.imageTag}"
              if skopeo --tmpdir "$tmpdir" --insecure-policy copy \
                nix:${image.oci} \
                docker-daemon:${image.oci.imageName}:${image.oci.imageTag} \
                "$@"; then
                exit 0
              fi

              echo "Direct Docker daemon copy failed; retrying via docker archive" >&2
              archive_dir="$(mktemp -d -p "$tmpdir" "devcontainer-${name}.XXXXXX")"
              trap 'rm -rf "$archive_dir"' EXIT
              archive="$archive_dir/image.tar"
              skopeo --tmpdir "$tmpdir" --insecure-policy copy \
                nix:${image.oci} \
                docker-archive:"$archive":${image.oci.imageName}:${image.oci.imageTag} \
                "$@"
              docker load -i "$archive"
            '';
          };
        in
        lib.nameValuePair "load-${name}" {
          type = "app";
          program = "${loadImage}/bin/load-${name}";
        }
      ) images;
      imagePackages = lib.mapAttrs' (
        name: image: lib.nameValuePair "devcontainer-${name}" image.oci
      ) images;
      reportChecks = lib.mapAttrs' (
        name: image:
        lib.nameValuePair "reports-${imageNameToCheckName name}" (
          pkgs.runCommand "reports-${name}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            export CHECK_SMOKE_PLAN=${./tests/ci/check-smoke-plan.py}
            python3 ${./tests/ci/check-reports.py} ${image.reports} ${name}
            touch "$out"
          ''
        )
      ) images;
      reportCliChecks = lib.mapAttrs' (
        name: image:
        lib.nameValuePair "report-cli-${imageNameToCheckName name}" (
          pkgs.runCommand "report-cli-${name}"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.jq
              ];
            }
            ''
              bash ${./tests/ci/check-report-cli.sh} ${
                compiler.runtimePackages."devcontainer-image"
              } ${image.reports} ${name}
              touch "$out"
            ''
        )
      ) images;
      imageBuildChecks = lib.mapAttrs' (
        name: image:
        lib.nameValuePair "image-${imageNameToCheckName name}" (
          pkgs.runCommand "image-${name}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            python3 ${./tests/ci/check-image-tar.py} ${image.oci} ${name}
            touch "$out"
          ''
        )
      ) (lib.filterAttrs (name: _: builtins.elem name [ "nix" ]) images);
      runtimeToolChecks = {
        runtime-tools =
          pkgs.runCommand "runtime-tools"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gnugrep
              ];
            }
            ''
              export DEVCONTAINER_FLAKE=${./.}
              export DEVCONTAINER_PROJECTOR=${compiler.runtimePackages."vscode-extension-projector"}
              export DEVCONTAINER_RUNNER=${compiler.runtimePackages."devcontainer-task-runner"}
              export DEVCONTAINER_DEVPKG=${compiler.runtimePackages.devpkg}
              bash ${./tests/ci/check-runtime-tools.sh}
              touch "$out"
            '';
        runtime-validation-scripts =
          pkgs.runCommand "runtime-validation-scripts"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gnugrep
              ];
            }
            ''
              bash ${./tests/ci/check-runtime-validation-scripts.sh} ${./.}
              touch "$out"
            '';
        runtime-evidence-validator =
          pkgs.runCommand "runtime-evidence-validator"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.python3
              ];
            }
            ''
              bash ${./tests/ci/check-runtime-evidence-validator.sh} ${./.}
              touch "$out"
            '';
      };
      fixtureFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
        builtins.readDir ./tests/fixtures
      );
      fixtureChecks = lib.mapAttrs' (
        name: _:
        let
          fixture = import (./tests/fixtures + "/${name}") { inherit self; };
          missing = builtins.filter (
            node: !(builtins.hasAttr node fixture.image.graph.nodes)
          ) fixture.expectedNodes;
        in
        lib.nameValuePair "fixture-${lib.replaceStrings [ ".nix" "-" ] [ "" "_" ] name}" (
          assert missing == [ ];
          pkgs.writeText "fixture-${name}.json" (
            builtins.toJSON {
              image = fixture.image.config.devcontainer.image.name;
              expectedNodes = fixture.expectedNodes;
              missing = missing;
            }
          )
        )
      ) fixtureFiles;
    in
    {
      formatter.${system} = pkgs.nixfmt-rfc-style;

      images = images;

      packages.${system} = imagePackages // {
        default = images.nix.reports;
        "devcontainer-image" = compiler.runtimePackages."devcontainer-image";
        "devcontainer-task-runner" = compiler.runtimePackages."devcontainer-task-runner";
        "vscode-extension-projector" = compiler.runtimePackages."vscode-extension-projector";
        devpkg = compiler.runtimePackages.devpkg;
      };

      apps.${system} = imageLoadApps // {
        default = imageLoadApps."load-nix";
      };

      checks.${system} =
        reportChecks // reportCliChecks // imageBuildChecks // runtimeToolChecks // fixtureChecks;

      lib.${system} = {
        inherit imageNames;
        vscodeExtensionSources = builtins.attrNames nix-vscode-extensions.extensions.${system};
        nix2container = nix2container.packages.${system}.nix2container;
      };
    };
}
