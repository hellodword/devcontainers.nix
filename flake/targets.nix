{ pkgs, lib }:

let
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
      module = ../images/nix.nix;
    })
    (mkImageTarget {
      target = "go-latest";
      family = "go";
      tags = [
        "latest"
        goLatestVersion
      ];
      module = ../images/go.nix;
      extraModules = goLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "go-${versionTarget goPrevious.version}";
      family = "go";
      tags = [ goPrevious.version ];
      module = ../images/go.nix;
      extraModules = [
        (goVersionModule goPrevious.package)
      ]
      ++ commonLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "go-web";
      family = "go";
      tags = [ "web" ];
      module = ../images/go-web.nix;
      extraModules = goLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "nodejs-latest";
      family = "nodejs";
      tags = [
        "latest"
        nodejsLatestVersion
      ];
      module = ../images/nodejs.nix;
      extraModules = commonLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "nodejs-${nodejsPrevious.version}";
      family = "nodejs";
      tags = [ nodejsPrevious.version ];
      module = ../images/nodejs.nix;
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
      module = ../images/python.nix;
      extraModules = commonLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "python-web";
      family = "python";
      tags = [ "web" ];
      module = ../images/python-web.nix;
      extraModules = commonLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "rust-latest";
      family = "rust";
      tags = [ "latest" ];
      module = ../images/rust.nix;
      extraModules = rustLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "rust-web";
      family = "rust";
      tags = [ "web" ];
      module = ../images/rust-web.nix;
      extraModules = rustLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "flutter-latest";
      family = "flutter";
      tags = [ "latest" ];
      module = ../images/flutter.nix;
      extraModules = rustLatestRuntimeModules;
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
