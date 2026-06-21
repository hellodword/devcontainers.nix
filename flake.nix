{
  description = "Devcontainer Nix/OCI image compiler";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
      nix-index-database,
      llm-agents,
      nix2container,
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
      projectOverlays = [ ];
      nixpkgsOverlays = [
        nix-vscode-extensions.overlays.default
        (final: prev: {
          inherit (nix2container.packages.${system})
            nix2container
            skopeo-nix2container
            ;
        })
        rust-overlay.overlays.default
        nix-index-database.overlays.nix-index
        llm-agents.overlays.default
      ]
      ++ projectOverlays;
      pkgs = import nixpkgs {
        inherit system;
        config = nixpkgsConfig;
        overlays = nixpkgsOverlays;
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

      targets = import ./flake/targets.nix { inherit pkgs lib; };
      images = lib.mapAttrs (
        _: target: compiler.mkImage { inherit (target) modules; }
      ) targets.imageTargets;
      workflows = import ./flake/workflows.nix {
        inherit pkgs lib;
        imageNames = targets.imageNames;
      };
      flakeChecks = import ./flake/checks.nix {
        inherit
          self
          pkgs
          lib
          nixpkgs
          compiler
          images
          ;
      };

      imageLoadApps = lib.mapAttrs' (
        name: image:
        let
          loadImage = pkgs.writeShellApplication {
            name = "load-${name}";
            runtimeInputs = [
              pkgs.docker
              pkgs.jq
              pkgs.skopeo-nix2container
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
      nixfmtFormatter = pkgs.writeShellApplication {
        name = "nixfmt";
        runtimeInputs = [
          pkgs.findutils
          pkgs.nixfmt
        ];
        text = ''
          if [ "$#" -eq 0 ]; then
            find . -path ./result -prune -o -name '*.nix' -type f -print0 | xargs -0 nixfmt
          else
            nixfmt "$@"
          fi
        '';
      };
    in
    {
      formatter.${system} = nixfmtFormatter;

      images = images;

      packages.${system} = imagePackages // {
        default = images."nix-latest".reports;
        "devcontainer-image" = compiler.runtimePackages."devcontainer-image";
        "devcontainer-gui-env" = compiler.runtimePackages."devcontainer-gui-env";
        "devcontainer-task-runner" = compiler.runtimePackages."devcontainer-task-runner";
        "vscode-extension-projector" = compiler.runtimePackages."vscode-extension-projector";
        devpkg = compiler.runtimePackages.devpkg;
        generate-workflows = workflows.generateWorkflows;
      };

      apps.${system} = imageLoadApps // {
        default = imageLoadApps."load-nix-latest";
        generate-workflows = {
          type = "app";
          program = "${workflows.generateWorkflows}/bin/generate-workflows";
        };
      };

      checks.${system} = flakeChecks // {
        generated-workflows = workflows.generatedWorkflowsCheck;
      };

      lib.${system} = {
        imageNames = targets.imageNames;
        vscodeExtensionSources = builtins.attrNames pkgs.nix-vscode-extensions;
        nix2container = compiler.nix2container;
      };
    };
}
