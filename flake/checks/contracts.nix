{
  pkgs,
  lib,
  compiler,
  images,
  targets,
  ...
}:

let
  repoRoot = ../..;
  reportLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: image: ''
      echo "checking reports for ${name}"
      python3 ${../../tests/ci/check-reports.py} ${image.reports} ${name}
    '') images
  );
  reportChecks = lib.mapAttrs' (
    name: image:
    lib.nameValuePair "reports-${name}" (
      pkgs.runCommand "reports-${name}"
        {
          nativeBuildInputs = [ pkgs.python3 ];
        }
        ''
          export CHECK_SMOKE_PLAN=${../../tests/ci/check-smoke-plan.py}
          python3 ${../../tests/ci/check-reports.py} ${image.reports} ${name}
          touch "$out"
        ''
    )
  ) images;
  smokePlanLines = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: image: ''
      echo "checking smoke plan for ${name}"
      python3 ${../../tests/ci/check-smoke-plan.py} ${image.smoke} ${image.profile-report-json} ${name}
    '') images
  );
  imageContracts = lib.mapAttrsToList (
    name: image:
    let
      plan = image.reportData.imagePlan;
      smoke = image.reportData.smokePlan;
    in
    {
      inherit name;
      family = plan.family;
      publishRefs = plan.publishRefs;
      smokeCapabilities = smoke.capabilities;
    }
  ) images;
  imageNames = builtins.attrNames images;
  targetNames = map (target: target.target) targets.imageTargetList;
  sortedTargetNames = lib.sort builtins.lessThan targetNames;
  uniqueTargetNames = lib.unique targetNames;
  nonEmptyString = value: builtins.isString value && value != "";
  targetRegistryContracts = map (
    target:
    let
      indexedTarget = targets.imageTargets.${target.target};
      imageConfig = images.${target.target}.config.devcontainer.image;
    in
    {
      name = target.target;
      registry = {
        inherit (target)
          family
          tags
          ;
        docsUseWhen = target.docs.useWhen or null;
      };
      compiled = {
        name = imageConfig.name;
        family = imageConfig.family;
        tags = imageConfig.tags;
      };
      indexedTargetMatches =
        indexedTarget.target == target.target
        && indexedTarget.family == target.family
        && indexedTarget.tags == target.tags
        && indexedTarget.docs.useWhen == target.docs.useWhen;
      docsValid = target ? docs && target.docs ? useWhen && nonEmptyString target.docs.useWhen;
      compiledMatches =
        imageConfig.name == target.target && imageConfig.family == target.family && imageConfig.tags == target.tags;
    }
  ) targets.imageTargetList;
  smokePlan = image: image.reportData.smokePlan;
  smokeCapabilities = image: (smokePlan image).capabilities;
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
      group = "99-fallback";
      packages = [ ];
      priority = 1;
      stability = "stable";
      sharing = "single-image";
      securityClass = "trusted";
    }
    // attrs;
  previousTargets = builtins.filter (
    name:
    (lib.hasPrefix "go-" name && name != "go" && name != "go-web")
    || (lib.hasPrefix "nodejs-" name && name != "nodejs")
  ) imageNames;
  # Publishing policy: these public image targets must remain exposed.
  requiredImageFamiliesOrTargets = [
    "nix"
    "go"
    "go-web"
    "nodejs"
    "python3"
    "python3-web"
    "rust"
    "rust-web"
    "flutter"
  ];
  latestSuffixTargets = builtins.filter (name: lib.hasSuffix "-latest" name) imageNames;

  apiEvalImage = compiler.mkImage {
    modules = [
      ../../images/nix.nix
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
      ../../images/python.nix
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
  customLocaleImage = compiler.mkImage {
    modules = [
      ../../images/nix.nix
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
      ../../images/nix.nix
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
  shellFeatureCapabilities = smokeCapabilities shellFeatureEvalImage;
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
  flutterCoreCapabilities = smokeCapabilities flutterCoreEvalImage;
  nixCapabilities = smokeCapabilities images."nix";

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
                    group = "80-vscode-extensions-base";
                    packages = [ ];
                    priority = 1;
                    stability = "stable";
                    sharing = "single-image";
                    securityClass = "trusted";
                    vscode.extensions."redhat.vscode-yaml" = {
                      native = false;
                      bucket = "80-vscode-extensions-base";
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
  publishedExtensionOriginViolations = lib.concatMap (
    name:
    map
      (extension: {
        image = name;
        extension = extension.id;
        origins = extension.origins or [ ];
      })
      (
        builtins.filter (
          extension: builtins.length (extension.origins or [ ]) != 1
        ) images.${name}.vscodeExtensions.extensions
      )
  ) imageNames;
  prettierOriginViolations = lib.concatMap (
    name:
    map
      (extension: {
        image = name;
        origins = extension.origins or [ ];
      })
      (
        builtins.filter (
          extension:
          extension.id == "esbenp.prettier-vscode" && (extension.origins or [ ]) != [ "editor/prettier" ]
        ) images.${name}.vscodeExtensions.extensions
      )
  ) imageNames;
  justExtension = extensionById images."nix" "nefrob.vscode-just-syntax";
  pythonExtensionIds = map (extension: extension.id) images."python3".vscodeExtensions.extensions;
in
reportChecks
// {
  contracts-reports-all =
    pkgs.runCommand "contracts-reports-all" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        export CHECK_SMOKE_PLAN=${../../tests/ci/check-smoke-plan.py}
        ${reportLines}
        touch "$out"
      '';

  contracts-smoke-plan-all =
    pkgs.runCommand "contracts-smoke-plan-all" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        ${smokePlanLines}
        touch "$out"
      '';

  contracts-hermetic-checks =
    pkgs.runCommand "contracts-hermetic-checks" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${../../tests/ci/check-hermetic-default-checks.py} ${repoRoot}
        touch "$out"
      '';

  contracts-image-targets =
    assert builtins.length previousTargets >= 2;
    assert latestSuffixTargets == [ ];
    assert targetNames == targets.imageNames;
    assert sortedTargetNames == imageNames;
    assert builtins.length uniqueTargetNames == builtins.length targetNames;
    assert lib.all nonEmptyString targetNames;
    assert lib.all (contract: contract.indexedTargetMatches) targetRegistryContracts;
    assert lib.all (contract: contract.docsValid) targetRegistryContracts;
    assert lib.all (contract: contract.compiledMatches) targetRegistryContracts;
    assert lib.all (name: builtins.elem name imageNames) requiredImageFamiliesOrTargets;
    assert lib.all (
      name:
      (builtins.match "go-[0-9]+_[0-9]+" name != null) || (builtins.match "nodejs-[0-9]+" name != null)
    ) previousTargets;
    assert lib.all (contract: contract.publishRefs != [ ]) imageContracts;
    assert lib.all (contract: contract.smokeCapabilities != [ ]) imageContracts;
    pkgs.writeText "contracts-image-targets.json" (
      builtins.toJSON {
        previousTargets = previousTargets;
        registry = targetRegistryContracts;
        images = imageContracts;
      }
    );

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
    assert publishedExtensionOriginViolations == [ ];
    assert prettierOriginViolations == [ ];
    assert justExtension.origins == [ "language/just" ];
    assert hasCompanionTools justExtension [
      "just"
      "just-lsp"
    ];
    assert !(builtins.elem "ms-python.autopep8" pythonExtensionIds);
    assert builtins.elem "uv" pythonRuntimeProfile.packages;
    assert builtins.elem "pip" pythonRuntimeProfile.packages;
    assert builtins.elem "runtime.python" pythonRuntimeProfile.tests.capabilities;
    assert builtins.hasAttr "runtime/python" pythonProfileEvalImage.graph.nodes;
    assert builtins.elem "pipx" pythonLanguageProfile.packages;
    assert pythonLanguageProfile.vscode.settings."python.defaultInterpreterPath" == "/usr/bin/python";
    assert builtins.elem "language.python" pythonLanguageProfile.tests.capabilities;
    assert builtins.hasAttr "language/python" pythonProfileEvalImage.graph.nodes;
    assert !(pythonExtension.native);
    assert builtins.elem "python" pythonExtension.companionTools;
    assert pythonProfileEvalImage.profileReport.validation.companionToolsProvidedByNix;
    assert lib.hasInfix "fr_FR.UTF-8" customLocaleCommand;
    assert lib.hasInfix "fr_FR:fr" customLocaleCommand;
    assert !(lib.hasInfix "en_US.UTF-8" customLocaleCommand);
    assert builtins.elem "shell.interactive" shellFeatureCapabilities;
    assert !(lib.hasInfix "bash-completion" shellFeatureInteractiveCommand);
    assert !(lib.hasInfix "command_not_found_handle" shellFeatureInteractiveCommand);
    assert !(lib.hasInfix "complete -p devpkg" shellFeatureDevpkgCommand);
    assert !(lib.hasInfix "complete -p git" shellFeatureEvalImage.shell.bashrcText);
    assert builtins.elem "language.flutter" flutterCoreCapabilities;
    assert !(builtins.elem "runtime.android-sdk" flutterCoreCapabilities);
    assert !(builtins.elem "runtime.browser-gui-gpu" flutterCoreCapabilities);
    assert !(builtins.elem "language.flutter-rust-bridge" flutterCoreCapabilities);
    assert builtins.elem "editor-support.tools" nixCapabilities;
    assert builtins.elem "workflow-format.tools" nixCapabilities;
    assert builtins.elem "nix-index.tools" nixCapabilities;
    assert builtins.elem "codex.cli" nixCapabilities;
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
