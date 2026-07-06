{
  pkgs,
  lib,
  nixpkgs,
  compiler,
  ...
}:

let
  envUtils = import ../../../lib/compiler/env-utils.nix { inherit lib; };
  libraryUtils = import ../../../lib/library-utils.nix { inherit lib; };
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
      ../../../images/nix.nix
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
                    command = ../../../runtime/devcontainer-gui-env/main.sh;
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
      ../../../images/python.nix
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

  customLocaleImage = compiler.mkImage {
    modules = [
      ../../../images/nix.nix
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
      ../../../images/nix.nix
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
      extraNixLdLibraryPath = extraNixLdLibrariesImage.fhsRuntime.nixLdEnv.NIX_LD_LIBRARY_PATH;
      lifecycleTimeout = lifecycleTimeoutTask.timeoutSeconds;
      fontAlias = fontAliasReport.fontconfig.aliases.Helvetica;
    }
  );
in
{
  contracts-compiler-fhs-options =
    assert !(builtins.hasAttr "runtime/fhs-vscode" fhsDisabledImage.graph.nodes);
    assert builtins.filter (id: lib.hasPrefix "fhs." id) (smokeCaseIds fhsDisabledImage) == [ ];
    assert fhsDisabledImage.fhsRuntime.symlinks == [ ];
    assert
      fhsDisabledImage.fhsRuntime.env == {
        container = { };
        remote = { };
        shell = { };
      };
    assert
      fhsDisabledImage.fhsRuntime.envOrigins == {
        container = { };
        remote = { };
        shell = { };
      };
    assert fhsDisabledImage.fhsRuntime.caCertificates == { };
    assert !(hasAnyAttr fhsEnvNames fhsDisabledImage.env.containerEnv);
    assert nixLdDisabledImage.fhsRuntime.dynamicLoaderMode == "glibc";
    assert !(hasAnyAttr nixLdEnvNames nixLdDisabledImage.fhsRuntime.env.container);
    assert !(hasAnyAttr nixLdEnvNames nixLdDisabledImage.env.containerEnv);
    assert
      symlinkSource "/lib64/ld-linux-x86-64.so.2" nixLdDisabledImage
      == nixLdDisabledImage.fhsRuntime.realGlibcLoader;
    assert hasSmokeCase "fhs.runtime" nixLdDisabledImage;
    assert !(hasSmokeCase "fhs.nix-ld" nixLdDisabledImage);
    assert caDisabledImage.fhsRuntime.caCertificates == { };
    assert !(hasAnyAttr caEnvNames caDisabledImage.fhsRuntime.env.container);
    assert !(hasAnyAttr caEnvNames caDisabledImage.env.containerEnv);
    assert !(hasSmokeCase "fhs.ca-certificates" caDisabledImage);
    assert hasSmokeCase "fhs.runtime" caDisabledImage;
    assert hasSmokeCase "fhs.nix-ld" caDisabledImage;
    assert customLoaderReport.dynamicLoader.target == customDynamicLoader;
    assert
      symlinkSource customDynamicLoader customLoaderImage
      == "${customLoaderImage.config.programs."nix-ld".package}/bin/nix-ld";
    assert lib.hasInfix customDynamicLoader (smokeCaseCommandText "fhs.nix-ld" customLoaderImage);
    assert customLoaderImage.fhsRuntime.nixLdEnv.NIX_LD == customLoaderImage.fhsRuntime.realGlibcLoader;
    assert lib.hasInfix "zlib" extraNixLdLibrariesImage.fhsRuntime.nixLdEnv.NIX_LD_LIBRARY_PATH;
    assert lifecycleTimeoutTask.timeoutSeconds == 123;
    assert lifecycleTasksJsonTask.timeoutSeconds == 123;
    assert fontAliasImage.fonts.report.fontconfig.aliases.Helvetica == fontAliasExpected;
    assert fontAliasReport.fontconfig.aliases.Helvetica == fontAliasExpected;
    pkgs.runCommand "contracts-compiler-fhs-options"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${../../../tests/ci/check-fontconfig-root.py} ${fontAliasImage.fonts.root} ${fontAliasImage.fontconfig-report-json} font-alias-eval
        cp ${fhsOptionsSummary} "$out"
      '';

  contracts-compiler-graph =
    assert builtins.attrNames graphDuplicateReport == [ graphDuplicateSharedPath ];
    assert
      graphDuplicateReport.${graphDuplicateSharedPath} == [
        "duplicate/first"
        "duplicate/second"
      ];
    assert !(builtins.hasAttr graphDuplicateRepeatedPath graphDuplicateReport);
    assert !(builtins.hasAttr graphDuplicateLeftPath graphDuplicateReport);
    assert !(builtins.hasAttr graphDuplicateRightPath graphDuplicateReport);
    pkgs.writeText "contracts-compiler-graph.json" (builtins.toJSON graphDuplicateReport);

  contracts-compiler-env =
    assert envExpansion.XDG_DATA_HOME == "/home/vscode/.local/share";
    assert envExpansion.BIN == "/home/vscode/.local/share/bin";
    assert envExpansion.PATH_LIST == "/home/vscode/.local/share/bin:/usr/bin";
    assert envExpansion.BRACED_SUFFIX == "tool-suffix";
    assert envExpansion.TAIL == "/opt/tool";
    assert envExpansion.EXTERNAL == "$DEVCONTAINER_WORKSPACE";
    assert remoteEnvExpansion.CHILD == "/base/child";
    assert remoteEnvExpansion.KEEP == "$UNDEFINED_REMOTE";
    assert envCycleRejected;
    assert envMaxDepthRejected;
    assert
      uniqueDrvPaths == [
        (displayDrv pkgs.hello)
        (displayDrv pkgs.git)
      ];
    assert withoutDrvPaths == [ (displayDrv pkgs.git) ];
    assert missingPresetEnvRejected;
    assert invalidEtcModeRejected;
    assert invalidEtcOwnerRejected;
    assert invalidEtcTargetRejected;
    assert invalidFilesystemPathRejected;
    assert invalidFilesystemModeRejected;
    assert invalidFilesystemOwnerRejected;
    assert apiEvalImage.env.workspace.lateBound;
    assert !(builtins.hasAttr "WORKSPACE" apiEvalImage.env.containerEnv);
    assert apiEvalImage.env.workspace.pathSegments == apiWorkspacePathSegments;
    assert
      apiEvalImage.env.staticPathSegments
      == builtins.filter (
        segment: !(builtins.elem segment apiEvalImage.env.workspace.pathSegments)
      ) apiEvalImage.env.pathSegments;
    assert
      apiEvalImage.env.containerEnv.PATH == lib.concatStringsSep ":" apiEvalImage.env.staticPathSegments;
    assert apiEvalImage.env.runtimePATH == lib.concatStringsSep ":" apiEvalImage.env.pathSegments;
    assert apiEvalImage.metadata.mergedPreview.containerEnv.WORKSPACE == "\${containerWorkspaceFolder}";
    assert apiEvalImage.env.containerEnv.API_BOOL == "1";
    assert apiEvalImage.env.containerEnv.TZDIR == "/etc/zoneinfo";
    assert
      apiEvalImage.env.containerEnv.DEVCONTAINER_FLAKE_INPUTS
      == "/usr/share/devcontainer/flake-inputs.json";
    assert apiEvalImage.flakeInputs.manifest.inputs.nixpkgs.rev == nixpkgs.rev;
    assert apiEvalImage.flakeInputs.manifest.inputs.nixpkgs.outPath == toString nixpkgs.outPath;
    assert builtins.elem "/etc/api/example.conf" (map (entry: entry.path) apiEvalImage.environment.etc);
    assert builtins.elem "man" apiEvalImage.environment.report.extraOutputsToInstall;
    assert lib.hasInfix "complete -p git" apiEvalImage.shell.bashrcText;
    assert lib.hasInfix "share/bash-completion/completions/git" apiEvalImage.shell.bashrcText;
    assert apiVscodeMachineSettings.settings == apiEvalImage.profiles.settings;
    assert pathCommandScript.command == builtins.readFile ../../../runtime/devcontainer-gui-env/main.sh;
    assert pathCommandScript.shell == "bash";
    assert !(pathCommandScript.interactive);
    assert defaultFieldsScript.command == "true";
    assert defaultFieldsScript.shell == "bash";
    assert !(defaultFieldsScript.interactive);
    assert apiVscodeMachineSettingsPaths == expectedVscodeMachineSettingsPaths;
    assert lib.all (
      entry:
      entry.rootMode == "1777"
      && entry.dataMode == "1777"
      && entry.machineMode == "1777"
      && entry.settingsMode == "0444"
      && entry.owner == "root:root"
    ) apiVscodeMachineSettings.paths;
    pkgs.writeText "contracts-compiler-env.json" (builtins.toJSON apiEvalImage.environment.report);

  contracts-compiler-profiles =
    assert builtins.elem "test/bundle-a" profileIncludeEvalImage.profileReport.rootEnabledProfileIds;
    assert builtins.elem "test/bundle-b" profileIncludeEvalImage.profileReport.rootEnabledProfileIds;
    assert builtins.elem "test/leaf-a" profileIncludeIds;
    assert builtins.elem "test/leaf-b" profileIncludeIds;
    assert builtins.length (builtins.filter (id: id == "test/leaf-a") profileIncludeIds) == 1;
    assert
      profileIncludeEvalImage.profileReport.includeGraph."test/bundle-a" == [
        "test/leaf-a"
        "test/leaf-b"
      ];
    assert
      profileIncludeLeafA.includedBy == [
        "test/bundle-a"
        "test/bundle-b"
      ];
    assert unknownIncludeRejected;
    assert includeCycleRejected;
    assert bundleResourcesRejected;
    assert leafIncludesRejected;
    assert justExtension.origins == [ "language/just" ];
    assert hasCompanionTools justExtension [
      "just"
      "just-lsp"
    ];
    assert !(builtins.elem "ms-python.autopep8" pythonExtensionIds);
    assert builtins.elem "uv" pythonRuntimeProfile.packages;
    assert builtins.elem "pip" pythonRuntimeProfile.packages;
    assert builtins.elem "runtime.python" pythonRuntimeProfile.tests.cases;
    assert builtins.hasAttr "runtime/python" pythonProfileEvalImage.graph.nodes;
    assert builtins.elem "pipx" pythonLanguageProfile.packages;
    assert pythonLanguageProfile.vscode.settings."python.defaultInterpreterPath" == "/usr/bin/python";
    assert builtins.elem "language.python" pythonLanguageProfile.tests.cases;
    assert builtins.hasAttr "language/python" pythonProfileEvalImage.graph.nodes;
    assert !(pythonExtension.native);
    assert builtins.elem "python" pythonExtension.companionTools;
    assert pythonProfileEvalImage.profileReport.validation.companionToolsProvidedByNix;
    assert lib.hasInfix "fr_FR.UTF-8" customLocaleCommand;
    assert lib.hasInfix "fr_FR:fr" customLocaleCommand;
    assert !(lib.hasInfix "en_US.UTF-8" customLocaleCommand);
    assert builtins.elem "shell.interactive" shellFeatureCaseIds;
    assert !(lib.hasInfix "bash-completion" shellFeatureInteractiveCommand);
    assert !(lib.hasInfix "command_not_found_handle" shellFeatureInteractiveCommand);
    assert !(lib.hasInfix "complete -p devpkg" shellFeatureDevpkgCommand);
    assert !(lib.hasInfix "complete -p git" shellFeatureEvalImage.shell.bashrcText);
    assert builtins.elem "language.flutter" flutterCoreCaseIds;
    assert !(builtins.elem "runtime.android-sdk" flutterCoreCaseIds);
    assert !(builtins.elem "runtime.browser-gui-gpu" flutterCoreCaseIds);
    assert !(builtins.elem "language.flutter-rust-bridge" flutterCoreCaseIds);
    pkgs.writeText "contracts-compiler-profiles.json" (
      builtins.toJSON {
        pythonLanguage = pythonLanguageProfile;
        pythonRuntime = pythonRuntimeProfile;
      }
    );

  contracts-compiler-metadata =
    assert apiEvalImage.metadata.mergedPreview.userEnvProbe == "loginInteractiveShell";
    assert !(builtins.hasAttr "PATH" (apiEvalImage.metadata.mergedPreview.containerEnv or { }));
    assert builtins.hasAttr "postStartCommand" apiEvalImage.metadata.mergedPreview;
    assert apiEvalImage.security.report.image == "api-eval";
    assert
      builtins.attrNames apiEvalImage.security.report.checks == [
        "dockerDaemon"
        "dockerSocket"
        "extensionArtifacts"
        "extensionProjectionLogRedaction"
        "lifecycleLogRedaction"
        "secretScan"
        "shellInitSideEffects"
        "workspaceConfigProtection"
      ];
    assert lib.all (
      check: check.status == "pass" && check.evidence.findingCount == 0 && check.evidence.findings == [ ]
    ) (builtins.attrValues apiEvalImage.security.report.checks);
    assert apiEvalImage.security.report.findings == [ ];
    assert invalidKnownHostsRejected;
    assert unsupportedSudoRejected;
    assert missingCompanionToolRejected;
    pkgs.writeText "contracts-compiler-metadata.json" (
      builtins.toJSON apiEvalImage.metadata.schemaReport
    );
}
