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
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
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
        withSystem,
        # moduleWithSystem,
        ...
      }:
      let
        withNix = true;
        commonFeats =
          (with self.lib.features; [
            (dev0 { })
            (dev1 { })
            (dev2 { })

            (prettier { })
            (markdown { })
            (xml { })
            (toml { })
            (jinja { })
            (protobuf { })

            (autocorrect { })
            (grammarly { })

            (shellcheck { })

            (drawio { })
            (graphviz { })

            (copilot { })
          ])
          ++ (if withNix then [ (self.lib.features.nix-core { }) ] else [ ]);
      in
      {
        imports = [ ];
        systems = [
          "x86_64-linux"
          # "aarch64-linux"
        ];

        flake = {
          lib = import ./lib;

          /*
            CC="zig cc -target x86_64-linux-gnu" GOOS=linux CGO_ENABLED=1 go build -o main.elf .
            ./main.elf

            CC="zig cc -target x86_64-windows-gnu" LD_LIBRARY_PATH="$WINDOWS_LD_LIBRARY_PATH:$LD_LIBRARY_PATH" PKG_CONFIG_PATH="$WINDOWS_PKG_CONFIG_PATH:$PKG_CONFIG_PATH" GOOS=windows CGO_ENABLED=1 CGO_LDFLAGS="-static -static-libgcc -static-libstdc++" go build -o main.exe .
            wine main.exe

            CC="gcc" GOOS=linux CGO_ENABLED=1 go build -o main.elf .
            ./main.elf

            CC="x86_64-w64-mingw32-gcc" LD_LIBRARY_PATH="$WINDOWS_LD_LIBRARY_PATH:$LD_LIBRARY_PATH" PKG_CONFIG_PATH="$WINDOWS_PKG_CONFIG_PATH:$PKG_CONFIG_PATH" GOOS=windows CGO_ENABLED=1 CGO_LDFLAGS="-static -static-libgcc -static-libstdc++" go build -o main.exe .
            wine main.exe
          */
          packages.x86_64-linux.frida-windows = withSystem "x86_64-linux" (
            { pkgs, ... }:
            self.lib.mkManuallyLayeredDevcontainer {
              inherit pkgs withNix;
              tag = "windows";
              name = "ghcr.io/hellodword/devcontainers-frida";
              features =
                commonFeats
                ++ (with self.lib.features; [
                  (go { goPackage = pkgs.go; })

                  # https://github.com/mstorsjo/msvc-wine/pull/187
                  (
                    { pkgs, ... }:
                    {
                      layered = true;
                      executables = with pkgs; [
                        wineWow64Packages.stable
                        python3
                        msitools
                        clang.cc
                        lld
                        samba
                      ];
                    }
                  )

                  (mingw64 { })
                  # override gcc of mingw stdenv
                  (cpp { })

                  (python {
                    pythonPackage = pkgs.python313;
                    # FATA[0180] committing the finished image: docker engine reported: "max depth exceeded"
                    layered = false;
                  })
                  (node {
                    nodePackage = pkgs.nodejs_latest;
                    layered = false;
                  })

                  (cmake { })
                  (wine { })
                  (clibs-win64 { })
                ]);
            }
          );

          packages.x86_64-linux.go-win64-zigcc = withSystem "x86_64-linux" (
            { pkgs, ... }:
            self.lib.mkManuallyLayeredDevcontainer {
              inherit pkgs withNix;
              tag = "win64-zigcc";
              name = "ghcr.io/hellodword/devcontainers-go";
              features =
                commonFeats
                ++ (with self.lib.features; [
                  (zigcc { })
                  (go { goPackage = pkgs.go; })
                  (
                    { ... }:
                    {
                      name = "zigcc-win64";
                      envVars = {
                        CGO_ENABLED = "1";
                        GOOS = "windows";
                        CC = "zig cc -target x86_64-windows-gnu";
                        CXX = "zig c++ -target x86_64-windows-gnu";
                      };
                    }
                  )
                  (wine { })
                  (clibs-win64 { })
                ]);
            }
          );

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
                allowUnsupportedSystem = true;
                # allowInsecurePredicate = (_: true);
              };

              overlays = [
                inputs.nix-vscode-extensions.overlays.default
                (prev: final: { inherit (inputs.nix2container.packages.${system}) nix2container; })
                inputs.rust-overlay.overlays.default
                inputs.nix-index-database.overlays.nix-index
              ];
            };

            apps =
              (builtins.listToAttrs (
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
              ))
              // {
                generate-github-actions = {
                  type = "app";
                  program = pkgs.writeShellApplication {
                    name = "exe";
                    runtimeInputs = with pkgs; [
                      coreutils
                      minijinja
                      jq
                    ];
                    text = ''
                      rm -rf .github/workflows/build-image-*.yml

                      IFS=" " read -r -a packages_amd64 <<< "$(nix eval --json $".#packages.x86_64-linux" --apply 'x: builtins.concatStringsSep " " (builtins.attrNames x)' | jq -r)"
                      IFS=" " read -r -a packages_arm64 <<< "$(nix eval --json $".#packages.aarch64-linux" --apply 'x: builtins.concatStringsSep " " (builtins.attrNames x)' | jq -r)"

                      for package in "${"$"}{packages_amd64[@]}"; do
                        found=false
                        for arm64_package in "${"$"}{packages_arm64[@]}"; do
                          if [[ "$package" == "$arm64_package" ]]; then
                            found=true
                            break
                          fi
                        done

                        args=()

                        if $found; then
                          args+=(-D systems="x86_64-linux,aarch64-linux")
                        else
                          args+=(-D systems="x86_64-linux")
                        fi

                        minijinja-cli .github/workflows/build-image.yml.j2 -D package="$package" -a none "${"$"}{args[@]}" | tee ".github/workflows/build-image-$package.yml"
                      done

                      for package in "${"$"}{packages_arm64[@]}"; do
                        found=false
                        for amd64_package in "${"$"}{packages_amd64[@]}"; do
                          if [[ "$package" == "$amd64_package" ]]; then
                            found=true
                            break
                          fi
                        done

                        if ! $found; then
                          minijinja-cli .github/workflows/build-image.yml.j2 -D package="$package" -a none -D systems="aarch64-linux" | tee ".github/workflows/build-image-$package.yml"
                        fi
                      done

                    '';
                  };
                };
              };

            packages = {

              base = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs;
                name = "ghcr.io/hellodword/devcontainers-base";
              };

              dev = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-dev";
                features = commonFeats;
              };

              nix = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-nix";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (nix { })
                  ]);
              };

              cpp = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-cpp";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (cpp { })
                    (cmake { })
                    (ninja { })
                    (meson { })
                    (gdb { })
                  ]);
              };

              vala = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-vala";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (cc { })
                    (vala { })
                    (ninja { })
                    (meson { })
                    (gdb { })
                  ]);
              };

              rust = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-rust";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (rust { })
                    (cpp { })
                  ]);
              };

              php = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-php";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (php { })
                  ]);
              };

              php-web = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-php";
                tag = "web";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (php { })
                    (node { nodePackage = pkgs.nodejs_latest; })
                  ]);
              };

              haskell = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-haskell";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (cc { })
                    (haskell { })
                  ]);
              };

              dart = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-dart";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (dart { })
                  ]);
              };

              lua = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-lua";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (lua { })
                  ]);
              };

              zig = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-zig";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (zig { })
                  ]);
              };

              writer = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-writer";
                features = commonFeats ++ [
                  (
                    { ... }:
                    {
                      vscodeSettings = {
                        "autocorrect.formatOnSave" = true;
                      };
                    }
                  )
                ];
              };

              latex = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-latex";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (latex { })
                  ]);
              };

              nginx = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                name = "ghcr.io/hellodword/devcontainers-nginx";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (nginx { })
                  ]);
              };

            }

            # https://nodejs.org/en/about/previous-releases
            // (
              let
                nodePackages = {
                  latest = pkgs.nodejs_latest;
                  "24" = pkgs.nodejs_24;
                  "22" = pkgs.nodejs_22;
                  "20" = pkgs.nodejs_20;
                };
              in
              builtins.listToAttrs (
                map (tag: {
                  name = "node${formatName tag}";
                  value = self.lib.mkManuallyLayeredDevcontainer {
                    inherit pkgs withNix tag;
                    name = "ghcr.io/hellodword/devcontainers-node";
                    features =
                      commonFeats
                      ++ (with self.lib.features; [
                        (node { nodePackage = nodePackages."${tag}"; })
                      ]);
                  };
                }) (builtins.attrNames nodePackages)
              )
            )

            # https://devguide.python.org/versions/
            // {
              python-web = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                tag = "web";
                name = "ghcr.io/hellodword/devcontainers-python";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (cc { })
                    (python { pythonPackage = pkgs.python313; })
                    (node { nodePackage = pkgs.nodejs_latest; })
                  ]);
              };
            }
            // (
              let
                pythonPackages = {
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
                    inherit pkgs withNix tag;
                    name = "ghcr.io/hellodword/devcontainers-python";
                    features =
                      commonFeats
                      ++ (with self.lib.features; [
                        (cc { })
                        (python { pythonPackage = pythonPackages."${tag}"; })
                      ]);
                  };
                }) (builtins.attrNames pythonPackages)
              )
            )

            // (
              let
                jdkPackages = {
                  latest = pkgs.jdk_headless;
                  "8" = pkgs.jdk8_headless;
                  "21" = pkgs.jdk21_headless;
                };
              in
              builtins.listToAttrs (
                map (tag: {
                  name = "java${formatName tag}";
                  value = self.lib.mkManuallyLayeredDevcontainer {
                    inherit pkgs withNix tag;
                    name = "ghcr.io/hellodword/devcontainers-java";
                    features =
                      commonFeats
                      ++ (with self.lib.features; [
                        (java { jdkPackage = jdkPackages."${tag}"; })
                      ]);
                  };
                }) (builtins.attrNames jdkPackages)
              )
            )

            // (
              let
                dotnetPackages = {
                  latest = pkgs.dotnet-sdk;
                  "8" = pkgs.dotnet-sdk_8;
                  "9" = pkgs.dotnet-sdk_9;
                  # "10" = pkgs.dotnet-sdk_10;
                };
              in
              builtins.listToAttrs (
                map (tag: {
                  name = "dotnet${formatName tag}";
                  value = self.lib.mkManuallyLayeredDevcontainer {
                    inherit pkgs withNix tag;
                    name = "ghcr.io/hellodword/devcontainers-dotnet";
                    features =
                      commonFeats
                      ++ (with self.lib.features; [
                        (dotnet { dotnetPackage = dotnetPackages."${tag}"; })
                      ]);
                  };
                }) (builtins.attrNames dotnetPackages)
              )
            )

            # Go and Go web
            # the latest two major versions
            # https://go.dev/doc/devel/release#policy
            # https://github.com/NixOS/nixpkgs/pull/384229
            // {
              go-web = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                tag = "web";
                name = "ghcr.io/hellodword/devcontainers-go";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (go { goPackage = pkgs.go; })
                    (node { nodePackage = pkgs.nodejs_latest; })
                  ]);
              };
              go-cc = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                tag = "cc";
                name = "ghcr.io/hellodword/devcontainers-go";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (cc { })
                    (go { goPackage = pkgs.go; })
                    (
                      { ... }:
                      {
                        name = "cgo-enabled";
                        envVars = {
                          CGO_ENABLED = "1";
                        };
                      }
                    )
                  ]);
              };
              go-zigcc = self.lib.mkManuallyLayeredDevcontainer {
                inherit pkgs withNix;
                tag = "zigcc";
                name = "ghcr.io/hellodword/devcontainers-go";
                features =
                  commonFeats
                  ++ (with self.lib.features; [
                    (zigcc { })
                    (go { goPackage = pkgs.go; })
                    (
                      { ... }:
                      {
                        name = "cgo-enabled";
                        envVars = {
                          CGO_ENABLED = "1";
                        };
                      }
                    )
                  ]);
              };
            }
            // (
              let
                lib = pkgs.lib;
                goLatest = pkgs.go;
                versionWithoutMinor = version: "1.${builtins.elemAt (lib.splitString "." version) 1}";
                goLastMajor = builtins.toString (
                  (lib.strings.toInt (builtins.elemAt (lib.splitString "." goLatest.version) 1)) - 1
                );
                goLast = pkgs."go_1_${goLastMajor}";
                goPackages = {
                  latest = goLatest;
                  "${versionWithoutMinor goLatest.version}" = goLatest;
                  "${versionWithoutMinor goLast.version}" = goLast;
                };
              in
              builtins.listToAttrs (
                map (tag: {
                  name = "go${formatName tag}";
                  value = self.lib.mkManuallyLayeredDevcontainer {
                    inherit pkgs withNix tag;
                    name = "ghcr.io/hellodword/devcontainers-go";
                    features =
                      commonFeats
                      ++ (with self.lib.features; [
                        (go { goPackage = goPackages."${tag}"; })
                      ]);
                  };
                }) (builtins.attrNames goPackages)
              )
            );

          };
      }
    );
}
