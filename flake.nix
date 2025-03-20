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

          let
            formatName =
              tag: "${if tag == "latest" then "" else "-${builtins.replaceStrings [ "." ] [ "_" ] tag}"}";
          in
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

            packages =
              {

                base = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-base";
                };

                dev = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-dev";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                  ];
                };

                nix = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-nix";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    nix
                  ];
                  withNix = true;
                };

                cpp = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-cpp";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    cpp
                  ];
                };

                vala = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-vala";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    vala
                  ];
                };

                rust = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-rust";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    rust
                  ];
                };

                php = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-php";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    php
                  ];
                };

                php-web = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-php";
                  tag = "web";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    php
                    (node pkgs.nodejs-slim_latest)
                  ];
                };

                haskell = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-haskell";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    haskell
                  ];
                };

                dart = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-dart";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    dart
                  ];
                };

                lua = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-lua";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    lua
                  ];
                };

                zig = self.lib.mkManuallyLayeredDevcontainer {
                  inherit pkgs;
                  name = "ghcr.io/hellodword/devcontainers-zig";
                  features = with self.lib.features; [
                    dev0
                    dev1
                    dev2
                    zig
                  ];
                };

              }

              # https://devguide.python.org/versions/
              // (
                let
                  nodePkgs = {
                    latest = pkgs.nodejs-slim_latest;
                    "23" = pkgs.nodejs-slim_23;
                    "22" = pkgs.nodejs-slim_22;
                    "20" = pkgs.nodejs-slim_20;
                    "18" = pkgs.nodejs-slim_18;
                  };
                in
                builtins.listToAttrs (
                  map (tag: {
                    name = "node${formatName tag}";
                    value = self.lib.mkManuallyLayeredDevcontainer {
                      inherit pkgs tag;
                      name = "ghcr.io/hellodword/devcontainers-node";
                      features = with self.lib.features; [
                        dev0
                        dev1
                        dev2
                        (node nodePkgs."${tag}")
                      ];
                    };
                  }) (builtins.attrNames nodePkgs)
                )
              )

              # https://devguide.python.org/versions/
              // (
                let
                  pyPkgs = {
                    latest = pkgs.python313;
                    # "3.10" = pkgs.python310;
                    "3.11" = pkgs.python311;
                    "3.12" = pkgs.python312;
                    "3.13" = pkgs.python313;
                    # # wait for fixes
                    # "3.14" = pkgs.python314;
                  };
                in
                builtins.listToAttrs (
                  map (tag: {
                    name = "python${formatName tag}";
                    value = self.lib.mkManuallyLayeredDevcontainer {
                      inherit pkgs tag;
                      name = "ghcr.io/hellodword/devcontainers-python";
                      features = with self.lib.features; [
                        dev0
                        dev1
                        dev2
                        (python pyPkgs."${tag}")
                      ];
                    };
                  }) (builtins.attrNames pyPkgs)
                )
              )

              // (
                let
                  jdkPkgs = {
                    latest = pkgs.jdk_headless;
                    "8" = pkgs.jdk8_headless;
                    "21" = pkgs.jdk21_headless;
                  };
                in
                builtins.listToAttrs (
                  map (tag: {
                    name = "java${formatName tag}";
                    value = self.lib.mkManuallyLayeredDevcontainer {
                      inherit pkgs tag;
                      name = "ghcr.io/hellodword/devcontainers-java";
                      features = with self.lib.features; [
                        dev0
                        dev1
                        dev2
                        (java jdkPkgs."${tag}")
                      ];
                    };
                  }) (builtins.attrNames jdkPkgs)
                )
              )

              // (
                let
                  dotnetCores = {
                    latest = pkgs.dotnet-sdk;
                    "8" = pkgs.dotnet-sdk_8;
                    "9" = pkgs.dotnet-sdk_9;
                    "10" = pkgs.dotnet-sdk_10;
                  };
                in
                builtins.listToAttrs (
                  map (tag: {
                    name = "dotnet${formatName tag}";
                    value = self.lib.mkManuallyLayeredDevcontainer {
                      inherit pkgs tag;
                      name = "ghcr.io/hellodword/devcontainers-dotnet";
                      features = with self.lib.features; [
                        dev0
                        dev1
                        dev2
                        (dotnet dotnetCores."${tag}")
                      ];
                    };
                  }) (builtins.attrNames dotnetCores)
                )
              )

              # Go and Go web
              # the latest two major versions
              # https://go.dev/doc/devel/release#policy
              # https://github.com/NixOS/nixpkgs/pull/384229
              // (
                let
                  lib = pkgs.lib;
                  goLatest = pkgs.go;
                  versionWithoutMinor = version: "1.${builtins.elemAt (lib.splitString "." version) 1}";
                  goLastMajor = builtins.toString (
                    (lib.strings.toInt (builtins.elemAt (lib.splitString "." goLatest.version) 1)) - 1
                  );
                  goLast = pkgs."go_1_${goLastMajor}";
                  goPkgs = {
                    latest = goLatest;
                    "${versionWithoutMinor goLatest.version}" = goLatest;
                    "${versionWithoutMinor goLast.version}" = goLast;
                  };
                in
                builtins.listToAttrs (
                  (map (tag: {
                    name = "go${formatName tag}";
                    value = self.lib.mkManuallyLayeredDevcontainer {
                      inherit pkgs tag;
                      name = "ghcr.io/hellodword/devcontainers-go";
                      features = with self.lib.features; [
                        dev0
                        dev1
                        dev2
                        (go goPkgs."${tag}")
                      ];
                    };
                  }) (builtins.attrNames goPkgs))
                  ++ (map (tag: {
                    name = "go${formatName tag}-web";
                    value = self.lib.mkManuallyLayeredDevcontainer {
                      inherit pkgs;
                      tag = "${tag}-web";
                      name = "ghcr.io/hellodword/devcontainers-go";
                      features = with self.lib.features; [
                        dev0
                        dev1
                        dev2
                        (go goPkgs."${tag}")
                        (node pkgs.nodejs-slim_latest)
                      ];
                    };
                  }) (builtins.attrNames goPkgs))
                )
              );

          };
      }
    );
}
