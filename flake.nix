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

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
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
      treefmt-nix,
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
      };
      projectOverlays = [
        # (final: prev: { })
      ];
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
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

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

      collectInputNixConfig =
        {
          inputs,
          inputNames ? lib.genAttrs (builtins.attrNames (removeAttrs inputs [ "self" ])) (_: [ ]),
        }:
        let
          selectedInputs = lib.filterAttrs (
            name: value:
            builtins.hasAttr name inputNames
            && value ? outPath
            && builtins.pathExists (value.outPath + "/flake.nix")
          ) (removeAttrs inputs [ "self" ]);

          flakeNixOf = input: import (input.outPath + "/flake.nix");

          nixConfigs = lib.mapAttrsToList (
            name: input:
            let
              flake = flakeNixOf input;
            in
            {
              inherit name;
              config = flake.nixConfig or { };
            }
          ) selectedInputs;

          asList = value: if builtins.isList value then value else [ value ];

          matchesInputKeywords =
            name: value:
            let
              keywords = asList inputNames.${name};
            in
            keywords == [ ] || lib.any (keyword: lib.hasInfix keyword value) keywords;

          readList =
            name: attrName: cfg:
            lib.filter (matchesInputKeywords name) (asList (cfg.${attrName} or [ ]));

          collect =
            attrNames:
            lib.unique (
              lib.flatten (
                map (
                  { name, config }:
                  lib.flatten (map (attrName: readList name attrName config) attrNames)
                ) nixConfigs
              )
            );
        in
        {
          substituters = collect [
            "substituters"
            "extra-substituters"
            "trusted-substituters"
            "extra-trusted-substituters"
          ];

          trustedPublicKeys = collect [
            "trusted-public-keys"
            "extra-trusted-public-keys"
          ];
        };

      inheritedNixConfig =
        let
          collected = collectInputNixConfig {
            inherit inputs;
            inputNames = {
              llm-agents = [ ".numtide.com" ];
              agents-misc = [ "hellodword-codex.cachix.org" ];
              nix-vscode-extensions = [ "nix-community.cachix.org" ];
            };
          };
        in
        collected
        // {
          settings =
            (lib.optionalAttrs (collected.substituters != [ ]) {
              extra-substituters = collected.substituters;
            })
            // (lib.optionalAttrs (collected.trustedPublicKeys != [ ]) {
              extra-trusted-public-keys = collected.trustedPublicKeys;
            });
        };
      inheritedNixConfigModule =
        { lib, ... }:
        {
          config = lib.optionalAttrs (inheritedNixConfig.settings != { }) {
            nix.settings = lib.mapAttrs (_: value: lib.mkAfter value) inheritedNixConfig.settings;
          };
        };
    in
    {
      formatter.${system} = treefmtEval.config.build.wrapper;

      images = images;

      e2e.${system} = e2ePackages;

      packages.${system} =
        imagePackages
        // runtimePublicPackages
        // {
          default = images."nix".reports;
          generate-docs = docs.generateDocs;
        };

      apps.${system} = imageLoadApps // {
        default = imageLoadApps."load-nix";
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

      checks.${system} = flakeChecks;

      lib.${system} = {
        imageNames = targets.imageNames;
        inheritedNixConfig = inheritedNixConfig;
        vscodeExtensionSources = builtins.attrNames pkgs.nix-vscode-extensions;
        nix2container = compiler.nix2container;
      };
    };
}
