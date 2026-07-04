{
  description = "Devcontainer Nix/OCI image compiler";

  nixConfig = {
    extra-substituters = [
      "https://hellodword-codex.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "hellodword-codex.cachix.org-1:0URmcnC9aynWh9+FJ2tf+HQloylGgZzPtrz3sttTTiQ="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

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

    agents-misc.url = "github:hellodword/agents-misc";
    llm-agents.url = "github:numtide/llm-agents.nix";

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
      agents-misc,
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
        permittedInsecurePackages =
          [ ]
          ++ (nixpkgs.lib.optionals (llm-agents.rev == "76b9956a4e357732178b3c9c471c259d4e7d5b63") [
            "pnpm-10.34.0"
          ]);
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
        agents-misc.overlays.default
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

      targets = import ./images { inherit pkgs lib; };
      images = lib.mapAttrs (
        _: target:
        compiler.mkImage {
          modules = target.modules ++ [ inheritedNixConfigModule ];
        }
      ) targets.imageTargets;
      workflows = import ./flake/workflows.nix {
        inherit pkgs lib targets;
      };
      docs = import ./flake/docs.nix {
        inherit
          pkgs
          lib
          targets
          ;
      };
      flakeChecks = import ./flake/checks.nix {
        inherit
          self
          pkgs
          lib
          nixpkgs
          compiler
          images
          targets
          workflows
          ;
      };
      e2ePackages = import ./flake/e2e.nix {
        inherit
          pkgs
          lib
          targets
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
          meta.description = "Load the ${name} devcontainer image into Docker";
        }
      ) images;
      imagePackages = lib.mapAttrs' (
        name: image: lib.nameValuePair "devcontainer-${name}" image.oci
      ) images;
      runtimePublicPackages = lib.mapAttrs' (name: helper: lib.nameValuePair name helper.package) (
        lib.filterAttrs (_: helper: helper.publicPackage) compiler.runtimeHelpers
      );
      smokePlanRunner = pkgs.writeShellApplication {
        name = "run-smoke-plan";
        runtimeInputs = [
          pkgs.docker
          pkgs.nix
        ];
        text = ''
          exec ${pkgs.python3}/bin/python3 ${./tests/smoke/run-plan.py} "$@"
        '';
      };
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

      collectInputNixConfig =
        {
          inputs,
          inputNames ? builtins.attrNames (removeAttrs inputs [ "self" ]),
        }:
        let
          selectedInputs = lib.filterAttrs (
            name: value:
            lib.elem name inputNames && value ? outPath && builtins.pathExists (value.outPath + "/flake.nix")
          ) (removeAttrs inputs [ "self" ]);

          flakeNixOf = input: import (input.outPath + "/flake.nix");

          nixConfigs = map (
            input:
            let
              flake = flakeNixOf input;
            in
            flake.nixConfig or { }
          ) (lib.attrValues selectedInputs);

          asList = value: if builtins.isList value then value else [ value ];

          readList = attrName: cfg: asList (cfg.${attrName} or [ ]);

          collect =
            attrNames:
            lib.unique (
              lib.flatten (map (cfg: lib.flatten (map (attrName: readList attrName cfg) attrNames)) nixConfigs)
            );
        in
        {
          substituters = collect [
            # "substituters"
            "extra-substituters"
          ];

          trustedSubstituters = collect [
            # "trusted-substituters"
            "extra-trusted-substituters"
          ];

          trustedPublicKeys = collect [
            # "trusted-public-keys"
            "extra-trusted-public-keys"
          ];
        };

      inheritedNixConfig = collectInputNixConfig {
        inherit inputs;
        inputNames = [
          "llm-agents"
          "agents-misc"
          "nix-vscode-extensions"
        ];
      };
      inheritedTrustedSubstituters = lib.unique (
        inheritedNixConfig.substituters ++ inheritedNixConfig.trustedSubstituters
      );
      inheritedNixConfigModule =
        { lib, ... }:
        {
          config = lib.mkMerge [
            (lib.optionalAttrs (inheritedTrustedSubstituters != [ ]) {
              nix.settings.extra-substituters = lib.mkAfter inheritedTrustedSubstituters;
              nix.settings.extra-trusted-substituters = lib.mkAfter inheritedTrustedSubstituters;
            })
            (lib.optionalAttrs (inheritedNixConfig.trustedPublicKeys != [ ]) {
              nix.settings.extra-trusted-public-keys = lib.mkAfter inheritedNixConfig.trustedPublicKeys;
            })
          ];
        };
    in
    {
      formatter.${system} = nixfmtFormatter;

      images = images;

      e2e.${system} = e2ePackages;

      packages.${system} =
        imagePackages
        // runtimePublicPackages
        // {
          default = images."nix".reports;
          generate-workflows = workflows.generateWorkflows;
          generate-docs = docs.generateDocs;
        };

      apps.${system} = imageLoadApps // {
        default = imageLoadApps."load-nix";
        generate-workflows = {
          type = "app";
          program = "${workflows.generateWorkflows}/bin/generate-workflows";
          meta.description = "Regenerate checked-in image build workflows";
        };
        generate-docs = {
          type = "app";
          program = "${docs.generateDocs}/bin/generate-docs";
          meta.description = "Regenerate checked-in documentation snippets";
        };
        run-smoke-plan = {
          type = "app";
          program = "${smokePlanRunner}/bin/run-smoke-plan";
          meta.description = "Run an image smoke-test plan against the host Docker daemon";
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
