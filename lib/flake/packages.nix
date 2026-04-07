{
  self,
  pkgs,
  withNix,
  commonFeats,
}:
let
  features = self.lib.features;
  mk =
    {
      imageName,
      tag ? "latest",
      featureList ? [ ],
    }:
    self.lib.mkManuallyLayeredDevcontainer {
      inherit pkgs withNix tag;
      name = imageName;
      features = commonFeats ++ featureList;
    };

  formatName =
    tag: "${if tag == "latest" then "" else "-${builtins.replaceStrings [ "." ] [ "_" ] tag}"}";

  androidComposition = self.lib.generateAndroidCompositionFromFlutter pkgs pkgs.flutter;

  mkCopilotDepFeats =
    {
      layered ? true,
    }:
    with features;
    [
      (python { inherit layered; })
      (node { inherit layered; })
    ];
in
{
  base = self.lib.mkManuallyLayeredDevcontainer {
    inherit pkgs;
    name = "ghcr.io/hellodword/devcontainers-base";
  };

  dev = mk {
    imageName = "ghcr.io/hellodword/devcontainers-dev";
    featureList = mkCopilotDepFeats { };
  };

  nix = mk {
    imageName = "ghcr.io/hellodword/devcontainers-nix";
    featureList =
      with features;
      [
        (nix { })
      ]
      ++ (mkCopilotDepFeats { });
  };

  cpp = mk {
    imageName = "ghcr.io/hellodword/devcontainers-cpp";
    featureList =
      with features;
      [
        (cpp { })
        (cmake { })
        (ninja { })
        (meson { })
        (gdb { })
      ]
      ++ (mkCopilotDepFeats { layered = false; });
  };

  rust = mk {
    imageName = "ghcr.io/hellodword/devcontainers-rust";
    featureList =
      with features;
      [
        (rust { })
        (cpp { })
      ]
      ++ (mkCopilotDepFeats { layered = false; });
  };

  php = mk {
    imageName = "ghcr.io/hellodword/devcontainers-php";
    featureList = with features; [
      (php { })
    ];
  };

  php-web = mk {
    imageName = "ghcr.io/hellodword/devcontainers-php";
    tag = "web";
    featureList = with features; [
      (php { })
      (node { })
    ];
  };

  dart = mk {
    imageName = "ghcr.io/hellodword/devcontainers-dart";
    featureList = with features; [
      (dart { })
    ];
  };

  zig = mk {
    imageName = "ghcr.io/hellodword/devcontainers-zig";
    featureList = with features; [
      (zig { })
    ];
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

  flutter-go = mk {
    imageName = "ghcr.io/hellodword/devcontainers-flutter";
    tag = "go";
    featureList = with features; [
      (dart { })
      (flutter { })
      (java {
        jdkPackage = pkgs.jdk17;
        layered = false;
      })
      (android-sdk {
        inherit androidComposition;
      })
      (zigcc { })
      (go { layered = false; })
      (
        { ... }:
        {
          name = "cgo-enabled";
          envVars = {
            CGO_ENABLED = "1";
          };
        }
      )
      (fontconfig { })
    ];
  };

  flutter-rust = mk {
    imageName = "ghcr.io/hellodword/devcontainers-flutter";
    tag = "rust";
    featureList = with features; [
      (dart { })
      (flutter { })
      (java {
        jdkPackage = pkgs.jdk17;
        layered = false;
      })
      (android-sdk {
        inherit androidComposition;
      })
      (rust { })
      (cpp { })
      (fontconfig { })
      (
        { pkgs, ... }:
        {
          name = "flutter_rust_bridge_codegen";
          layered = false;
          executables = with pkgs; [
            flutter_rust_bridge_codegen
            sqlite
            sqlx-cli
            sqlitebrowser
          ];
        }
      )
    ];
  };

  android = mk {
    imageName = "ghcr.io/hellodword/devcontainers-android";
    featureList = with features; [
      (java {
        jdkPackage = pkgs.jdk17;
      })
      (android-sdk {
        inherit androidComposition;
      })
    ];
  };

  frida-windows = mk {
    imageName = "ghcr.io/hellodword/devcontainers-frida";
    tag = "windows";
    featureList = with features; [
      (go { layered = false; })
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
      (cpp { })
      (python {
        pythonPackage = pkgs.python313;
        layered = false;
      })
      (node { layered = false; })
      (cmake { })
      (wine { })
      (clibs-win64 { layered = false; })
    ];
  };

  go-win64-zigcc = mk {
    imageName = "ghcr.io/hellodword/devcontainers-go";
    tag = "win64-zigcc";
    featureList = with features; [
      (zigcc { })
      (go { })
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
    ];
  };

  frida-android = mk {
    imageName = "ghcr.io/hellodword/devcontainers-frida";
    tag = "android";
    featureList = with features; [
      (go { layered = false; })
      (cpp { })
      (python {
        pythonPackage = pkgs.python313;
        layered = false;
      })
      (node { layered = false; })
      (
        { ... }:
        {
          layered = false;
          name = "android-tools";
          executables = with pkgs; [
            android-tools
            usbutils
          ];
        }
      )
    ];
  };
}
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
      value = mk {
        imageName = "ghcr.io/hellodword/devcontainers-node";
        inherit tag;
        featureList = with features; [
          (node { nodePackage = nodePackages.${tag}; })
        ];
      };
    }) (builtins.attrNames nodePackages)
  )
)
// {
  python-web = mk {
    imageName = "ghcr.io/hellodword/devcontainers-python";
    tag = "web";
    featureList = with features; [
      (cc { })
      (python { })
      (node { })
    ];
  };
}
// (
  let
    pythonPackages = {
      latest = pkgs.python3;
      "3.12" = pkgs.python312;
      "3.13" = pkgs.python313;
      "3.14" = pkgs.python314;
    };
  in
  builtins.listToAttrs (
    map (tag: {
      name = "python${formatName tag}";
      value = mk {
        imageName = "ghcr.io/hellodword/devcontainers-python";
        inherit tag;
        featureList = with features; [
          (cc { })
          (python { pythonPackage = pythonPackages.${tag}; })
        ];
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
      value = mk {
        imageName = "ghcr.io/hellodword/devcontainers-java";
        inherit tag;
        featureList = with features; [
          (java { jdkPackage = jdkPackages.${tag}; })
        ];
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
    };
  in
  builtins.listToAttrs (
    map (tag: {
      name = "dotnet${formatName tag}";
      value = mk {
        imageName = "ghcr.io/hellodword/devcontainers-dotnet";
        inherit tag;
        featureList = with features; [
          (dotnet { dotnetPackage = dotnetPackages.${tag}; })
        ];
      };
    }) (builtins.attrNames dotnetPackages)
  )
)
// {
  go-cc = mk {
    imageName = "ghcr.io/hellodword/devcontainers-go";
    tag = "cc";
    featureList = with features; [
      (cc { })
      (go { })
      (
        { ... }:
        {
          name = "cgo-enabled";
          envVars = {
            CGO_ENABLED = "1";
          };
        }
      )
    ];
  };

  go-zigcc = mk {
    imageName = "ghcr.io/hellodword/devcontainers-go";
    tag = "zigcc";
    featureList = with features; [
      (zigcc { })
      (go { })
      (
        { ... }:
        {
          name = "cgo-enabled";
          envVars = {
            CGO_ENABLED = "1";
          };
        }
      )
    ];
  };
}
// (
  let
    lib = pkgs.lib;
    goLatest = pkgs.go_latest;
    versionWithoutMinor = version: "1.${builtins.elemAt (lib.splitString "." version) 1}";
    goLastMajor = toString (
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
      value = mk {
        imageName = "ghcr.io/hellodword/devcontainers-go";
        inherit tag;
        featureList =
          with features;
          [
            (go { goPackage = goPackages.${tag}; })
          ]
          ++ (mkCopilotDepFeats { });
      };
    }) (builtins.attrNames goPackages)
  )
)
