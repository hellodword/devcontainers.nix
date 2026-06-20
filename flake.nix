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

      major = version: builtins.elemAt (lib.splitVersion version) 0;
      majorMinor =
        version:
        let
          parts = lib.splitVersion version;
        in
        "${builtins.elemAt parts 0}.${builtins.elemAt parts 1}";
      versionTarget = version: lib.replaceStrings [ "." ] [ "-" ] version;

      sortedGoVersions =
        let
          attrs = builtins.filter (name: builtins.match "go_[0-9]+_[0-9]+" name != null) (
            builtins.attrNames pkgs
          );
          mkEntry =
            attr:
            let
              match = builtins.match "go_([0-9]+)_([0-9]+)" attr;
            in
            {
              inherit attr;
              version = "${builtins.elemAt match 0}.${builtins.elemAt match 1}";
              package = builtins.getAttr attr pkgs;
            };
        in
        lib.sort (a: b: lib.versionOlder b.version a.version) (map mkEntry attrs);
      goLatestPackage = if pkgs ? go_latest then pkgs.go_latest else pkgs.go;
      goLatestVersion = majorMinor goLatestPackage.version;
      goPrevious = lib.findFirst (
        entry: entry.version != goLatestVersion
      ) (throw "nixpkgs must expose a previous Go major.minor package") sortedGoVersions;

      sortedNodejsVersions =
        let
          attrs = builtins.filter (name: builtins.match "nodejs_[0-9]+" name != null) (
            builtins.attrNames pkgs
          );
          isEvenMajor =
            version:
            builtins.elem (lib.substring (builtins.stringLength version - 1) 1 version) [
              "0"
              "2"
              "4"
              "6"
              "8"
            ];
          mkEntry =
            attr:
            let
              match = builtins.match "nodejs_([0-9]+)" attr;
            in
            {
              inherit attr;
              version = builtins.elemAt match 0;
              package = builtins.getAttr attr pkgs;
            };
        in
        lib.sort (a: b: lib.versionOlder b.version a.version) (
          builtins.filter (entry: isEvenMajor entry.version) (map mkEntry attrs)
        );
      nodejsLatestPackage =
        if pkgs ? nodejs_latest then pkgs.nodejs_latest else (builtins.head sortedNodejsVersions).package;
      nodejsLatestVersion = major nodejsLatestPackage.version;
      nodejsPrevious = lib.findFirst (
        entry: entry.version != nodejsLatestVersion
      ) (throw "nixpkgs must expose a previous Node.js major package") sortedNodejsVersions;

      pythonLatestPackage = pkgs.python3;
      pythonLatestPackageSet = pkgs.python3Packages;
      pythonLatestVersion = majorMinor pythonLatestPackage.version;

      rustNightlyToolchain = pkgs.rust-bin.nightly.latest.default.override {
        extensions = [
          "rust-src"
          "rustfmt"
          "clippy"
          "rust-analyzer"
        ];
      };

      mkImageTarget =
        {
          target,
          family,
          tags,
          module,
          extraModules ? [ ],
        }:
        {
          inherit
            target
            family
            tags
            module
            extraModules
            ;
          modules = [
            module
            (
              { lib, ... }:
              {
                config.devcontainer.image = {
                  name = lib.mkForce target;
                  family = lib.mkForce family;
                  tags = lib.mkForce tags;
                };
              }
            )
          ]
          ++ extraModules;
        };
      goVersionModule = package: { ... }: {
        config.devcontainer.languages.go.package = package;
      };
      nodejsVersionModule = package: { ... }: {
        config.devcontainer.runtimes.nodejs.package = package;
      };
      pythonVersionModule = package: packageSet: { ... }: {
        config.devcontainer.runtimes.python.package = package;
        config.devcontainer.languages.python.packageSet = packageSet;
      };
      rustVersionModule = toolchain: { ... }: {
        config.devcontainer.languages.rust.toolchain = toolchain;
      };

      commonLatestRuntimeModules = [
        (pythonVersionModule pythonLatestPackage pythonLatestPackageSet)
        (nodejsVersionModule nodejsLatestPackage)
      ];
      goLatestRuntimeModules = [
        (goVersionModule goLatestPackage)
      ]
      ++ commonLatestRuntimeModules;
      rustLatestRuntimeModules = [
        (rustVersionModule rustNightlyToolchain)
      ]
      ++ commonLatestRuntimeModules;

      imageTargetList = [
        (mkImageTarget {
          target = "nix-latest";
          family = "nix";
          tags = [ "latest" ];
          module = ./images/nix.nix;
        })
        (mkImageTarget {
          target = "go-latest";
          family = "go";
          tags = [
            "latest"
            goLatestVersion
          ];
          module = ./images/go.nix;
          extraModules = goLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "go-${versionTarget goPrevious.version}";
          family = "go";
          tags = [ goPrevious.version ];
          module = ./images/go.nix;
          extraModules = [
            (goVersionModule goPrevious.package)
          ]
          ++ commonLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "go-web";
          family = "go";
          tags = [ "web" ];
          module = ./images/go-web.nix;
          extraModules = goLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "nodejs-latest";
          family = "nodejs";
          tags = [
            "latest"
            nodejsLatestVersion
          ];
          module = ./images/nodejs.nix;
          extraModules = commonLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "nodejs-${nodejsPrevious.version}";
          family = "nodejs";
          tags = [ nodejsPrevious.version ];
          module = ./images/nodejs.nix;
          extraModules = [
            (pythonVersionModule pythonLatestPackage pythonLatestPackageSet)
            (nodejsVersionModule nodejsPrevious.package)
          ];
        })
        (mkImageTarget {
          target = "python3";
          family = "python";
          tags = [
            "latest"
            pythonLatestVersion
          ];
          module = ./images/python.nix;
          extraModules = commonLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "python-web";
          family = "python";
          tags = [ "web" ];
          module = ./images/python-web.nix;
          extraModules = commonLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "rust-latest";
          family = "rust";
          tags = [ "latest" ];
          module = ./images/rust.nix;
          extraModules = rustLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "rust-web";
          family = "rust";
          tags = [ "web" ];
          module = ./images/rust-web.nix;
          extraModules = rustLatestRuntimeModules;
        })
        (mkImageTarget {
          target = "flutter-latest";
          family = "flutter";
          tags = [ "latest" ];
          module = ./images/flutter.nix;
          extraModules = rustLatestRuntimeModules;
        })
      ];
      imageTargets = lib.listToAttrs (
        map (target: lib.nameValuePair target.target target) imageTargetList
      );
      imageNames = map (target: target.target) imageTargetList;
      images = lib.mapAttrs (_: target: compiler.mkImage { inherit (target) modules; }) imageTargets;
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
            python3 ${./tests/ci/check-image-tar.py} ${image.oci} ${image.reports} ${name}
            touch "$out"
          ''
        )
      ) (lib.filterAttrs (name: _: builtins.elem name [ "nix-latest" ]) images);
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
              export DEVPKG_NIXPKGS_REF=path:${nixpkgs.outPath}
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
                pkgs.python3
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

      imageNameArray = lib.concatMapStringsSep "\n" (
        name: "                ${lib.escapeShellArg name}"
      ) imageNames;
      generateWorkflows = pkgs.writeShellApplication {
        name = "generate-workflows";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.minijinja
        ];
        text = ''
          workflow_dir=".github/workflows"
          template="$workflow_dir/_build-image.yml.j2"
          mkdir -p "$workflow_dir"
          find "$workflow_dir" -maxdepth 1 -type f -name 'build-image-*.yml' -delete
          test -f "$template"

          targets=(
          ${imageNameArray}
          )

          for target in "''${targets[@]}"; do
            minijinja-cli \
              --strict \
              --autoescape none \
              --syntax variable-start='<<' \
              --syntax variable-end='>>' \
              --define image_target="$target" \
              --output "$workflow_dir/build-image-$target.yml" \
              "$template"
          done
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
    in
    {
      formatter.${system} = nixfmtFormatter;

      images = images;

      packages.${system} = imagePackages // {
        default = images."nix-latest".reports;
        "devcontainer-image" = compiler.runtimePackages."devcontainer-image";
        "devcontainer-task-runner" = compiler.runtimePackages."devcontainer-task-runner";
        "vscode-extension-projector" = compiler.runtimePackages."vscode-extension-projector";
        devpkg = compiler.runtimePackages.devpkg;
        generate-workflows = generateWorkflows;
      };

      apps.${system} = imageLoadApps // {
        default = imageLoadApps."load-nix-latest";
        generate-workflows = {
          type = "app";
          program = "${generateWorkflows}/bin/generate-workflows";
        };
      };

      checks.${system} =
        reportChecks // reportCliChecks // imageBuildChecks // runtimeToolChecks // fixtureChecks;

      lib.${system} = {
        inherit imageNames;
        vscodeExtensionSources = builtins.attrNames nix-vscode-extensions.extensions.${system};
        nix2container = compiler.nix2container;
      };
    };
}
