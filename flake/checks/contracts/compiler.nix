{
  pkgs,
  lib,
  compiler,
  ...
}:

let
  smokePlan = image: image.reportData.smokePlan;
  smokeCaseIds = image: (smokePlan image).caseIds;
  smokeCase =
    id: image:
    lib.findFirst (test: test.id == id) (throw "missing smoke case ${id}") (smokePlan image).tests;
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
  pythonLanguageProfile = lib.findFirst (
    profile: profile.id == "language/python"
  ) (throw "language/python profile missing") pythonProfileEvalImage.profileReport.enabledProfiles;
  pythonRuntimeProfile = lib.findFirst (
    profile: profile.id == "runtime/python"
  ) (throw "runtime/python profile missing") pythonProfileEvalImage.profileReport.enabledProfiles;
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
  customLocaleCommand = lib.concatStringsSep " " (smokeCase "shell.locale" customLocaleImage).command;

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
  shellFeatureInteractiveCommand = lib.concatStringsSep " " (smokeCase "shell.interactive" shellFeatureEvalImage)
  .command;
  shellFeatureDevpkgCommand = lib.concatStringsSep " " (smokeCase "devpkg.core" shellFeatureEvalImage)
  .command;

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
  profileIncludeIds = map (profile: profile.id) profileIncludeEvalImage.profileReport.enabledProfiles;
  profileIncludeLeafA = lib.findFirst (
    profile: profile.id == "test/leaf-a"
  ) (throw "test/leaf-a missing") profileIncludeEvalImage.profileReport.enabledProfiles;
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
            command = [ "true" ];
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
in
{
  contracts-compiler-env =
    assert apiEvalImage.env.containerEnv.API_BOOL == "1";
    assert apiEvalImage.env.containerEnv.TZDIR == "/etc/zoneinfo";
    assert builtins.elem "/etc/api/example.conf" (map (entry: entry.path) apiEvalImage.environment.etc);
    assert builtins.elem "man" apiEvalImage.environment.report.extraOutputsToInstall;
    assert lib.hasInfix "complete -p git" apiEvalImage.shell.bashrcText;
    assert lib.hasInfix "share/bash-completion/completions/git" apiEvalImage.shell.bashrcText;
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
    assert invalidKnownHostsRejected;
    assert unsupportedSudoRejected;
    assert missingCompanionToolRejected;
    pkgs.writeText "contracts-compiler-metadata.json" (
      builtins.toJSON apiEvalImage.metadata.schemaReport
    );
}
