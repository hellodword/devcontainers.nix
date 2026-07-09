{
  pkgs,
  lib,
  nixpkgs,
  compiler,
  ...
}:

let
  envUtils = import ../../../../lib/compiler/env-utils.nix { inherit lib; };
  libraryUtils = import ../../../../lib/library-utils.nix { inherit lib; };
  displayDrv = drv: libraryUtils.displayPathString drv;
  smokePlan = image: image.reportData.smokePlan;
  smokeCaseIds = image: (smokePlan image).caseIds;
  smokeCase =
    id: image:
    lib.findFirst (test: test.id == id) (throw "missing smoke case ${id}") (smokePlan image).tests;
  hasSmokeCase = id: image: builtins.elem id (smokeCaseIds image);
  smokeCaseCommandText =
    id: image: lib.concatStringsSep " " (map (script: script.command) (smokeCase id image).scripts);
  symlinkSource =
    target: image:
    (lib.findFirst (
      link: link.target == target
    ) (throw "missing FHS symlink ${target}") image.fhsRuntime.symlinks).source;
  hasAnyAttr = names: attrs: lib.any (name: builtins.hasAttr name attrs) names;
  extensionById =
    image: id:
    lib.findFirst (
      extension: extension.id == id
    ) (throw "missing VS Code extension ${id}") image.vscodeExtensions.extensions;
  hasCompanionTools =
    extension: tools: lib.all (tool: builtins.elem tool extension.companionTools) tools;
  testProfile =
    attrs:
    {
      kind = "test";
      group = "fallback";
      packages = [ ];
      priority = 1;
      stability = "stable";
      sharing = "single-image";
      securityClass = "trusted";
    }
    // attrs;
  testGraphNode = paths: {
    kind = "test";
    group = "fallback";
    target = "host";
    stability = "stable";
    sharing = "single-image";
    priority = 1;
    securityClass = "trusted";
    inherit paths;
    files = { };
  };
  envExpansion = envUtils.expandEnv {
    scope = "contracts.env-utils";
    env = {
      HOME = "/home/vscode";
      XDG_DATA_HOME = "$HOME/.local/share";
      NAME = "tool";
      BIN = "${"$"}{XDG_DATA_HOME}/bin";
      PATH_LIST = [
        "$BIN"
        "/usr/bin"
      ];
      BRACED_SUFFIX = "${"$"}{NAME}-suffix";
      TAIL = "/opt/$NAME";
      EXTERNAL = "$DEVCONTAINER_WORKSPACE";
    };
  };
  remoteEnvExpansion = envUtils.expandEnvWithContext {
    scope = "contracts.env-utils.remote";
    context = {
      BASE = "/base";
      PATH = "/bin:/usr/bin";
    };
    env = {
      CHILD = "$BASE/child";
      KEEP = "$UNDEFINED_REMOTE";
    };
  };
  envCycleRejected =
    !(builtins.tryEval (
      builtins.deepSeq (envUtils.expandEnv {
        scope = "contracts.env-utils.cycle";
        env = {
          A = "$B";
          B = "$A";
        };
      }) null
    )).success;
  envMaxDepthRejected =
    !(builtins.tryEval (
      builtins.deepSeq (envUtils.expandEnv {
        scope = "contracts.env-utils.max-depth";
        maxDepth = 1;
        env = {
          A = "$B";
          B = "$C";
          C = "done";
        };
      }) null
    )).success;
  uniqueDrvPaths = map displayDrv (
    libraryUtils.uniqueDrvs [
      pkgs.hello
      pkgs.git
      pkgs.hello
    ]
  );
  withoutDrvPaths = map displayDrv (
    libraryUtils.withoutDrvs
      [ pkgs.hello ]
      [
        pkgs.hello
        pkgs.git
      ]
  );
  missingPresetEnvRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.compileLibraries {
          config.devcontainer.libraries = {
            runtime = [ ];
            build = [ ];
            exportLdLibraryPath = false;
            ccWrapperFlags = true;
            presets = [ "missing-preset" ];
            dynamicRuntimeProfile = "$XDG_DATA_HOME/devpkg/runtime-libraries/profile";
            dynamicBuildProfile = "$XDG_DATA_HOME/devpkg/build-libraries/profile";
          };
          compiledEnvironment.variables.XDG_DATA_HOME = "/home/vscode/.local/share";
          compiledProfiles.libraryPresets = [ ];
        }).env
        null
    )).success;
  environmentEtcRejected =
    module:
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [ module ];
        }).environment.etc
        null
    )).success;
  filesystemRejected =
    module:
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [ module ];
        }).filesystem.directories
        null
    )).success;
  invalidEtcModeRejected = environmentEtcRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "invalid-etc-mode";
        environment.etc.bad = {
          text = "bad\n";
          mode = "0999";
        };
      };
    }
  );
  invalidEtcOwnerRejected = environmentEtcRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "invalid-etc-owner";
        environment.etc.bad = {
          text = "bad\n";
          uid = -1;
        };
      };
    }
  );
  invalidEtcTargetRejected = environmentEtcRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "invalid-etc-target";
        environment.etc.bad = {
          target = "/tmp/bad";
          text = "bad\n";
        };
      };
    }
  );
  invalidFilesystemPathRejected = filesystemRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "invalid-filesystem-path";
        devcontainer.filesystem.directories."relative/path" = {
          mode = "0755";
          uid = 0;
          gid = 0;
        };
      };
    }
  );
  invalidFilesystemModeRejected = filesystemRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "invalid-filesystem-mode";
        devcontainer.filesystem.directories."/invalid-mode" = {
          mode = "8888";
          uid = 0;
          gid = 0;
        };
      };
    }
  );
  invalidFilesystemOwnerRejected = filesystemRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "invalid-filesystem-owner";
        devcontainer.filesystem.directories."/invalid-owner" = {
          mode = "0755";
          uid = 0;
          gid = -1;
        };
      };
    }
  );
  graphDuplicateSharedPath = "/nix/store/test-shared";
  graphDuplicateRepeatedPath = "/nix/store/test-repeated";
  graphDuplicateLeftPath = "/nix/store/test-left";
  graphDuplicateRightPath = "/nix/store/test-right";
  graphDuplicateEval = compiler.compileGraph {
    config.devcontainer.graph.nodes = {
      "duplicate/first" = testGraphNode [ graphDuplicateSharedPath ];
      "duplicate/second" = testGraphNode [ graphDuplicateSharedPath ];
      "duplicate/repeated-in-node" = testGraphNode [
        graphDuplicateRepeatedPath
        graphDuplicateRepeatedPath
      ];
      "duplicate/multiple-paths" = testGraphNode [
        graphDuplicateLeftPath
        graphDuplicateRightPath
      ];
    };
  };
  graphDuplicateReport = graphDuplicateEval.duplicates;

  apiEvalImage = compiler.mkImage {
    modules = [
      ../../../../images/nix.nix
      (
        { pkgs, lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "api-eval";
              family = lib.mkForce "api";
              tags = lib.mkForce [ "eval" ];
            };
            environment.systemPackages = [ pkgs.hello ];
            environment.pathsToLink = [
              "/bin"
              "/share"
              "/man"
            ];
            environment.extraOutputsToInstall = [
              "man"
              "dev"
            ];
            environment.variables.API_BOOL = true;
            environment.variableOrigins.API_BOOL = [ "tests.api" ];
            environment.etc."api/example.conf".text = "enabled\n";
            environment.shellInit = "export API_SHELL_INIT=1";
            environment.interactiveShellInit = "export API_INTERACTIVE_SHELL_INIT=1";
            programs.git.enable = true;
            programs.ssh.enable = true;
            programs.ssh.knownHosts.localhost.publicKey =
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexCodexCodexCodexCodexCodexCodexCodexCodex";
            programs.nix-index.enable = true;
            devcontainer.tests.cases = {
              "smoke.path-command" = {
                tags = [ "smoke" ];
                scripts = [
                  {
                    shell = "bash";
                    interactive = false;
                    command = ../../../../runtime/devcontainer-gui-env/main.sh;
                  }
                ];
              };
              "smoke.default-script-fields" = {
                tags = [ "smoke" ];
                scripts = [
                  {
                    command = "true";
                  }
                ];
              };
            };
          };
        }
      )
    ];
  };

  pythonProfileEvalImage = compiler.mkImage {
    modules = [
      ../../../../images/python.nix
      (
        { lib, ... }:
        {
          config.devcontainer.image = {
            name = lib.mkForce "profile-python-eval";
            family = lib.mkForce "test";
            tags = lib.mkForce [ "eval" ];
          };
        }
      )
    ];
  };
  pythonLanguageProfile =
    lib.findFirst (profile: profile.id == "language/python") (throw "language/python profile missing")
      pythonProfileEvalImage.profileReport.effectiveEnabledProfiles;
  pythonRuntimeProfile =
    lib.findFirst (profile: profile.id == "runtime/python") (throw "runtime/python profile missing")
      pythonProfileEvalImage.profileReport.effectiveEnabledProfiles;
  pythonExtension = lib.findFirst (
    extension: extension.id == "ms-python.python"
  ) (throw "ms-python.python extension missing") pythonProfileEvalImage.vscodeExtensions.extensions;
  pythonExtensionIds = map (
    extension: extension.id
  ) pythonProfileEvalImage.vscodeExtensions.extensions;

  cppProfileEvalImage = compiler.mkImage {
    modules = [
      ../../../../images/nix.nix
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "profile-cpp-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.profiles."language/cpp".enable = true;
          };
        }
      )
    ];
  };
  cppCoreProfile =
    lib.findFirst (profile: profile.id == "language/cpp/core")
      (throw "language/cpp/core profile missing")
      cppProfileEvalImage.profileReport.effectiveEnabledProfiles;
  cppSmokeProfile =
    lib.findFirst (profile: profile.id == "language/cpp/smoke")
      (throw "language/cpp/smoke profile missing")
      cppProfileEvalImage.profileReport.effectiveEnabledProfiles;
  cppClangdExtension = extensionById cppProfileEvalImage "llvm-vs-code-extensions.vscode-clangd";
  cppCmakeExtension = extensionById cppProfileEvalImage "ms-vscode.cmake-tools";
  cppLldbExtension = extensionById cppProfileEvalImage "vadimcn.vscode-lldb";

  customLocaleImage = compiler.mkImage {
    modules = [
      ../../../../images/nix.nix
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "custom-locale-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            i18n.defaultLocale = "fr_FR.UTF-8";
            i18n.language = "fr_FR:fr";
          };
        }
      )
    ];
  };
  pathCommandScript = builtins.head (smokeCase "smoke.path-command" apiEvalImage).scripts;
  defaultFieldsScript = builtins.head (smokeCase "smoke.default-script-fields" apiEvalImage).scripts;
  apiWorkspacePathSegments = [
    "$WORKSPACE/.devcontainer/bin"
    "$WORKSPACE/node_modules/.bin"
    "$WORKSPACE/.venv/bin"
  ];
  customLocaleCommand = smokeCaseCommandText "shell.locale" customLocaleImage;
  vscodeProjectionSuffix = "/extensions";
  vscodeMachineSettingsPathForProjectionTarget =
    target:
    assert lib.assertMsg (lib.hasSuffix vscodeProjectionSuffix target)
      "VS Code projection target must end with /extensions: ${target}";
    "${
      builtins.substring 0 (
        (builtins.stringLength target) - (builtins.stringLength vscodeProjectionSuffix)
      ) target
    }/data/Machine/settings.json";
  apiVscodeMachineSettings = apiEvalImage.filesystem.vscodeMachineSettings;
  apiVscodeMachineSettingsPaths = map (entry: entry.settingsPath) apiVscodeMachineSettings.paths;
  expectedVscodeMachineSettingsPaths = map vscodeMachineSettingsPathForProjectionTarget apiEvalImage.vscodeExtensions.projectionTargets;

  shellFeatureEvalImage = compiler.mkImage {
    modules = [
      ../../../../images/nix.nix
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "shell-feature-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            programs.bash.completion.enable = false;
            programs.bash.commandNotFound.enable = false;
          };
        }
      )
    ];
  };
  shellFeatureCaseIds = smokeCaseIds shellFeatureEvalImage;
  shellFeatureInteractiveCommand = smokeCaseCommandText "shell.interactive" shellFeatureEvalImage;
  shellFeatureDevpkgCommand = smokeCaseCommandText "devpkg.core" shellFeatureEvalImage;

  flutterCoreEvalImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "flutter-core-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.profiles."language/flutter".enable = true;
          };
        }
      )
    ];
  };
  flutterCoreCaseIds = smokeCaseIds flutterCoreEvalImage;

  justExtensionEvalImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "just-extension-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.profiles."toolset/workflow-format".enable = true;
          };
        }
      )
    ];
  };
  justExtension = extensionById justExtensionEvalImage "nefrob.vscode-just-syntax";

  invalidKnownHostsRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { ... }:
              {
                config = {
                  devcontainer.image.name = "invalid-known-hosts";
                  programs.ssh.enable = true;
                  programs.ssh.knownHosts.bad.publicKey = "";
                };
              }
            )
          ];
        }).environment.report
        null
    )).success;
  unsupportedSudoRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { ... }:
              {
                config = {
                  devcontainer.image.name = "unsupported-sudo";
                  security.sudo.enable = true;
                };
              }
            )
          ];
        }).config.security.sudo.enable
        null
    )).success;
  missingCompanionToolRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { lib, ... }:
              {
                config = {
                  devcontainer.image.name = "missing-companion-tool";
                  devcontainer.image.family = lib.mkForce "test";
                  devcontainer.profiles."test/extension" = {
                    enable = true;
                    kind = "test";
                    group = "vscode-extensions-base";
                    packages = [ ];
                    priority = 1;
                    stability = "stable";
                    sharing = "single-image";
                    securityClass = "trusted";
                    vscode.extensions."redhat.vscode-yaml" = {
                      native = false;
                      bucket = "vscode-extensions-base";
                      companionTools = [ "missing-tool" ];
                    };
                  };
                };
              }
            )
          ];
        }).profileReport
        null
    )).success;
  metadataRunArgsUserRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { ... }:
              {
                config = {
                  devcontainer.image.name = "metadata-runargs-user";
                  devcontainer.metadata.snippets = [
                    {
                      runArgs = [ "-u1000:100" ];
                    }
                  ];
                };
              }
            )
          ];
        }).metadata.label
        null
    )).success;
  profileIncludeEvalImage = compiler.mkImage {
    modules = [
      (
        { pkgs, lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "profile-include-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.profiles = {
              "test/bundle-a" = testProfile {
                enable = true;
                priority = 2;
                composition.role = "bundle";
                includes = [
                  "test/leaf-a"
                  "test/leaf-b"
                ];
              };
              "test/bundle-b" = testProfile {
                enable = true;
                composition.role = "bundle";
                includes = [ "test/leaf-a" ];
              };
              "test/leaf-a" = testProfile {
                packages = [ pkgs.hello ];
                priority = 3;
                provides.commands = [ "hello" ];
              };
              "test/leaf-b" = testProfile { };
            };
          };
        }
      )
    ];
  };
  profileIncludeIds = map (
    profile: profile.id
  ) profileIncludeEvalImage.profileReport.effectiveEnabledProfiles;
  profileIncludeLeafA = lib.findFirst (
    profile: profile.id == "test/leaf-a"
  ) (throw "test/leaf-a missing") profileIncludeEvalImage.profileReport.effectiveEnabledProfiles;
  profileEvalRejected =
    module:
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [ module ];
        }).profileReport
        null
    )).success;
  unknownIncludeRejected = profileEvalRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "unknown-include";
        devcontainer.image.family = lib.mkForce "test";
        devcontainer.profiles."test/bundle" = testProfile {
          enable = true;
          composition.role = "bundle";
          includes = [ "test/missing" ];
        };
      };
    }
  );
  includeCycleRejected = profileEvalRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "include-cycle";
        devcontainer.image.family = lib.mkForce "test";
        devcontainer.profiles = {
          "test/a" = testProfile {
            enable = true;
            composition.role = "bundle";
            includes = [ "test/b" ];
          };
          "test/b" = testProfile {
            composition.role = "bundle";
            includes = [ "test/a" ];
          };
        };
      };
    }
  );
  bundleResourcesRejected = profileEvalRejected (
    { pkgs, lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "bundle-resources";
        devcontainer.image.family = lib.mkForce "test";
        devcontainer.profiles."test/bundle" = testProfile {
          enable = true;
          packages = [ pkgs.hello ];
          composition.role = "bundle";
          provides.commands = [ "hello" ];
          vscode.settings."test.bundle" = true;
          env.variables.TEST_BUNDLE = "1";
          tests.cases."test.bundle" = {
            tags = [ "smoke" ];
            scripts = [
              {
                shell = "bash";
                interactive = false;
                command = "true";
              }
            ];
          };
        };
      };
    }
  );
  leafIncludesRejected = profileEvalRejected (
    { lib, ... }:
    {
      config = {
        devcontainer.image.name = lib.mkForce "leaf-includes";
        devcontainer.image.family = lib.mkForce "test";
        devcontainer.profiles = {
          "test/leaf" = testProfile {
            enable = true;
            includes = [ "test/other-leaf" ];
          };
          "test/other-leaf" = testProfile { };
        };
      };
    }
  );

  fhsEnvNames = [
    "NIX_LD"
    "NIX_LD_LIBRARY_PATH"
    "SSL_CERT_FILE"
    "NIX_SSL_CERT_FILE"
    "CURL_CA_BUNDLE"
    "GIT_SSL_CAINFO"
  ];
  caEnvNames = [
    "SSL_CERT_FILE"
    "NIX_SSL_CERT_FILE"
    "CURL_CA_BUNDLE"
    "GIT_SSL_CAINFO"
  ];
  nixLdEnvNames = [
    "NIX_LD"
    "NIX_LD_LIBRARY_PATH"
  ];
  fhsDisabledImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "fhs-disabled-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.compat.fhsRuntime.enable = false;
          };
        }
      )
    ];
  };
  nixLdDisabledImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "nix-ld-disabled-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            programs.nix-ld.enable = false;
          };
        }
      )
    ];
  };
  caDisabledImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "ca-disabled-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            security.pki.installCACerts = false;
          };
        }
      )
    ];
  };
  customDynamicLoader = "/custom/lib64/ld-linux-x86-64.so.2";
  customLoaderImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "custom-loader-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            programs.nix-ld.dynamicLoader.x86_64.path = customDynamicLoader;
          };
        }
      )
    ];
  };
  customLoaderReport = builtins.fromJSON (
    builtins.unsafeDiscardStringContext (builtins.readFile customLoaderImage.fhs-runtime-report-json)
  );
  extraNixLdLibrariesImage = compiler.mkImage {
    modules = [
      (
        { lib, pkgs, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "extra-nix-ld-libraries-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            programs.nix-ld.libraries = [ pkgs.zlib ];
          };
        }
      )
    ];
  };
  lifecycleTimeoutImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "lifecycle-timeout-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.lifecycle.tasks."contract-timeout" = {
              phase = "postCreate";
              command = [ "true" ];
              timeoutSeconds = 123;
            };
          };
        }
      )
    ];
  };
  lifecycleTimeoutTask = lib.findFirst (
    task: task.name == "contract-timeout"
  ) (throw "missing contract-timeout lifecycle task") lifecycleTimeoutImage.lifecycle.tasks;
  lifecycleTasksJson = builtins.fromJSON (
    builtins.unsafeDiscardStringContext (builtins.readFile lifecycleTimeoutImage.tasks-json)
  );
  lifecycleTasksJsonTask = lib.findFirst (
    task: task.name == "contract-timeout"
  ) (throw "missing contract-timeout tasks.json task") lifecycleTasksJson.tasks;
  fontAliasExpected = {
    binding = "strong";
    prefer = [ "Noto Sans" ];
    accept = [ "Noto Sans CJK SC" ];
    default = [ "sans-serif" ];
  };
  fontAliasImage = compiler.mkImage {
    modules = [
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "font-alias-eval";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.fonts.fontconfig.aliases.Helvetica = fontAliasExpected;
          };
        }
      )
    ];
  };
  fontAliasReport = builtins.fromJSON (
    builtins.unsafeDiscardStringContext (builtins.readFile fontAliasImage.fontconfig-report-json)
  );
  fhsOptionsSummary = pkgs.writeText "contracts-compiler-fhs-options.json" (
    builtins.toJSON {
      fhsDisabled = {
        symlinkCount = builtins.length fhsDisabledImage.fhsRuntime.symlinks;
        smokeCaseIds = smokeCaseIds fhsDisabledImage;
      };
      nixLdDisabled = {
        dynamicLoaderMode = nixLdDisabledImage.fhsRuntime.dynamicLoaderMode;
        dynamicLoaderSource = symlinkSource "/lib64/ld-linux-x86-64.so.2" nixLdDisabledImage;
      };
      caDisabledSmokeCases = smokeCaseIds caDisabledImage;
      customLoader = customLoaderReport.dynamicLoader;
      extraNixLdLibraryPathInputs = extraNixLdLibrariesImage.fhsRuntime.nixLdLibraryPathInputs;
      lifecycleTimeout = lifecycleTimeoutTask.timeoutSeconds;
      fontAlias = fontAliasReport.fontconfig.aliases.Helvetica;
    }
  );
in
{
  inherit
    envUtils
    libraryUtils
    displayDrv
    smokePlan
    smokeCaseIds
    smokeCase
    hasSmokeCase
    smokeCaseCommandText
    symlinkSource
    hasAnyAttr
    extensionById
    hasCompanionTools
    testProfile
    testGraphNode
    envExpansion
    remoteEnvExpansion
    envCycleRejected
    envMaxDepthRejected
    uniqueDrvPaths
    withoutDrvPaths
    missingPresetEnvRejected
    environmentEtcRejected
    filesystemRejected
    invalidEtcModeRejected
    invalidEtcOwnerRejected
    invalidEtcTargetRejected
    invalidFilesystemPathRejected
    invalidFilesystemModeRejected
    invalidFilesystemOwnerRejected
    graphDuplicateSharedPath
    graphDuplicateRepeatedPath
    graphDuplicateLeftPath
    graphDuplicateRightPath
    graphDuplicateEval
    graphDuplicateReport
    apiEvalImage
    pythonProfileEvalImage
    pythonLanguageProfile
    pythonRuntimeProfile
    pythonExtension
    pythonExtensionIds
    cppProfileEvalImage
    cppCoreProfile
    cppSmokeProfile
    cppClangdExtension
    cppCmakeExtension
    cppLldbExtension
    customLocaleImage
    pathCommandScript
    defaultFieldsScript
    apiWorkspacePathSegments
    customLocaleCommand
    vscodeProjectionSuffix
    vscodeMachineSettingsPathForProjectionTarget
    apiVscodeMachineSettings
    apiVscodeMachineSettingsPaths
    expectedVscodeMachineSettingsPaths
    shellFeatureEvalImage
    shellFeatureCaseIds
    shellFeatureInteractiveCommand
    shellFeatureDevpkgCommand
    flutterCoreEvalImage
    flutterCoreCaseIds
    justExtensionEvalImage
    justExtension
    invalidKnownHostsRejected
    unsupportedSudoRejected
    missingCompanionToolRejected
    metadataRunArgsUserRejected
    profileIncludeEvalImage
    profileIncludeIds
    profileIncludeLeafA
    profileEvalRejected
    unknownIncludeRejected
    includeCycleRejected
    bundleResourcesRejected
    leafIncludesRejected
    fhsEnvNames
    caEnvNames
    nixLdEnvNames
    fhsDisabledImage
    nixLdDisabledImage
    caDisabledImage
    customDynamicLoader
    customLoaderImage
    customLoaderReport
    extraNixLdLibrariesImage
    lifecycleTimeoutImage
    lifecycleTimeoutTask
    lifecycleTasksJson
    lifecycleTasksJsonTask
    fontAliasExpected
    fontAliasImage
    fontAliasReport
    fhsOptionsSummary
    ;
}
