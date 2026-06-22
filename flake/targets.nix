{ pkgs, lib }:

let
  major = version: builtins.elemAt (lib.splitVersion version) 0;
  majorMinor =
    version:
    let
      parts = lib.splitVersion version;
    in
    "${builtins.elemAt parts 0}.${builtins.elemAt parts 1}";
  versionTarget = version: lib.replaceStrings [ "." ] [ "_" ] version;

  mkPackageVersionEntries =
    {
      attrPattern,
      versionFromMatch,
      versionFilter ? (_: true),
    }:
    let
      attrs = builtins.filter (name: builtins.match attrPattern name != null) (builtins.attrNames pkgs);
      mkEntry =
        attr:
        let
          match = builtins.match attrPattern attr;
          version = versionFromMatch match;
        in
        {
          inherit attr version;
          package = builtins.getAttr attr pkgs;
          targetSuffix = versionTarget version;
        };
    in
    lib.sort (a: b: lib.versionOlder b.version a.version) (
      builtins.filter (entry: versionFilter entry.version) (map mkEntry attrs)
    );

  previousVersionEntry =
    name: latestVersion: entries:
    lib.findFirst (
      entry: entry.version != latestVersion
    ) (throw "nixpkgs must expose a previous ${name} package") entries;

  sortedGoVersions = mkPackageVersionEntries {
    attrPattern = "go_([0-9]+)_([0-9]+)";
    versionFromMatch = match: "${builtins.elemAt match 0}.${builtins.elemAt match 1}";
  };
  goLatestPackage = if pkgs ? go_latest then pkgs.go_latest else pkgs.go;
  goLatestVersion = majorMinor goLatestPackage.version;
  goPrevious = previousVersionEntry "Go major.minor" goLatestVersion sortedGoVersions;

  sortedNodejsVersions =
    let
      isEvenMajor =
        version:
        builtins.elem (lib.substring (builtins.stringLength version - 1) 1 version) [
          "0"
          "2"
          "4"
          "6"
          "8"
        ];
    in
    mkPackageVersionEntries {
      attrPattern = "nodejs_([0-9]+)";
      versionFromMatch = match: builtins.elemAt match 0;
      versionFilter = isEvenMajor;
    };
  nodejsLatestPackage =
    if pkgs ? nodejs_latest then pkgs.nodejs_latest else (builtins.head sortedNodejsVersions).package;
  nodejsLatestVersion = major nodejsLatestPackage.version;
  nodejsPrevious = previousVersionEntry "Node.js major" nodejsLatestVersion sortedNodejsVersions;

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
      target = "nix";
      family = "nix";
      tags = [ "latest" ];
      module = ../images/nix.nix;
      extraModules = commonLatestRuntimeModules ++ [
        (
          { lib, ... }:
          {
            config.devcontainer.profiles = {
              "runtime/python".enable = lib.mkDefault true;
              "language/python".enable = lib.mkDefault true;
              "runtime/nodejs".enable = lib.mkDefault true;
            };
          }
        )
      ];
    })
    (mkImageTarget {
      target = "go";
      family = "go";
      tags = [
        "latest"
        goLatestVersion
      ];
      module = ../images/go.nix;
      extraModules = goLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "go-${goPrevious.targetSuffix}";
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
      target = "nodejs";
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
      family = "python3";
      tags = [
        "latest"
        pythonLatestVersion
      ];
      module = ../images/python.nix;
      extraModules = commonLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "python3-web";
      family = "python3";
      tags = [ "web" ];
      module = ../images/python3-web.nix;
      extraModules = commonLatestRuntimeModules;
    })
    (mkImageTarget {
      target = "rust";
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
      target = "flutter";
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
