{ pkgs, lib }:

let
  goLatestPackage = if pkgs ? go_latest then pkgs.go_latest else pkgs.go;
  nodejsLatestPackage = if pkgs ? nodejs_latest then pkgs.nodejs_latest else pkgs.nodejs;
  pythonLatestPackage = pkgs.python3;
  pythonLatestPackageSet = pkgs.python3Packages;
  rustNightlyToolchain = pkgs.rust-bin.selectLatestNightlyWith (
    toolchain:
    toolchain.default.override {
      extensions = [
        "rust-src"
        "rustfmt"
        "clippy"
        "rust-analyzer"
      ];
    }
  );

  mkImageTarget =
    {
      target,
      family,
      tags,
      module,
      docs,
      ci ? { },
      checks ? { },
      extraModules ? [ ],
    }:
    {
      inherit
        target
        family
        tags
        module
        docs
        ci
        checks
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

  latestToolchainModules = [
    ({ ... }: {
      config.devcontainer.languages.go.package = goLatestPackage;
    })
    ({ ... }: {
      config.devcontainer.runtimes.nodejs.package = nodejsLatestPackage;
    })
    ({ ... }: {
      config.devcontainer = {
        runtimes.python.package = pythonLatestPackage;
        languages.python.packageSet = pythonLatestPackageSet;
      };
    })
    ({ ... }: {
      config.devcontainer.languages.rust.toolchain = rustNightlyToolchain;
    })
  ];

  devRequiredProfiles = [
    "runtime/nix"
    "language/nix"
    "runtime/c-env"
    "runtime/python"
    "language/python"
    "runtime/nodejs"
    "language/nodejs"
    "language/go"
    "language/rust"
    "toolset/data-network"
    "image/dev"
  ];
  devRequiredCommands = [
    "nix"
    "python"
    "uv"
    "node"
    "npm"
    "pnpm"
    "eslint"
    "go"
    "gopls"
    "rustc"
    "cargo"
    "rust-analyzer"
    "http"
  ];

  imageTargetList = [
    (mkImageTarget {
      target = "dev";
      family = "dev";
      tags = [ "latest" ];
      module = ./dev.nix;
      docs.useWhen = "Use for Nix, Node.js and web, Go, Python, Rust, and general development workflows.";
      checks = {
        required = true;
        requiredProfiles = devRequiredProfiles;
        requiredCommands = devRequiredCommands;
      };
      extraModules = latestToolchainModules;
    })
    (mkImageTarget {
      target = "flutter";
      family = "flutter";
      tags = [ "latest" ];
      module = ./flutter.nix;
      docs.useWhen = "Use for Flutter, Dart, Android, and Chromium-backed web workflows; includes every dev image capability.";
      checks = {
        required = true;
        requiredProfiles = devRequiredProfiles ++ [
          "language/flutter"
          "runtime/android-sdk"
          "runtime/browser-gui-gpu"
          "language/flutter-rust-bridge"
        ];
        requiredCommands = devRequiredCommands ++ [
          "flutter"
          "dart"
        ];
        rootfsRequires = [
          "/usr/bin/flutter"
          "/usr/bin/rust-analyzer"
          "/usr/bin/go"
          "/usr/bin/node"
          "/usr/bin/python"
        ];
      };
      extraModules = latestToolchainModules;
    })
  ];
in
{
  inherit imageTargetList;
  imageTargets = lib.listToAttrs (
    map (target: lib.nameValuePair target.target target) imageTargetList
  );
  imageNames = map (target: target.target) imageTargetList;
}
