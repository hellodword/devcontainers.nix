{
  self,
  pkgs,
  lib,
  nixpkgs,
  compiler,
  images,
}:

let
  repoRoot = ../.;
  fixturesDir = ../tests/fixtures;
  imageNameToCheckName = name: lib.replaceStrings [ "-" ] [ "_" ] name;

  reportChecks = lib.mapAttrs' (
    name: image:
    lib.nameValuePair "reports-${imageNameToCheckName name}" (
      pkgs.runCommand "reports-${name}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        export CHECK_SMOKE_PLAN=${../tests/ci/check-smoke-plan.py}
        python3 ${../tests/ci/check-reports.py} ${image.reports} ${name}
        touch "$out"
      ''
    )
  ) images;

  reportCliChecks = lib.mapAttrs' (
    name: image:
    lib.nameValuePair "report-cli-${imageNameToCheckName name}" (
      pkgs.runCommand "report-cli-${name}"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.jq
          ];
        }
        ''
          bash ${../tests/ci/check-report-cli.sh} ${
            compiler.runtimePackages."devcontainer-image"
          } ${image.reports} ${name}
          touch "$out"
        ''
    )
  ) images;

  imageBuildChecks = lib.mapAttrs' (
    name: image:
    lib.nameValuePair "image-${imageNameToCheckName name}" (
      pkgs.runCommand "image-${name}"
        {
          nativeBuildInputs = [
            pkgs.gnugrep
            pkgs.nix
            pkgs.python3
          ];
        }
        ''
          python3 ${../tests/ci/check-image-tar.py} ${image.oci} ${image.reports} ${name}
          nix-store -q --references ${image.oci} | grep -F ${lib.escapeShellArg nixpkgs.outPath} >/dev/null
          touch "$out"
        ''
    )
  ) (lib.filterAttrs (name: _: builtins.elem name [ "nix-latest" ]) images);

  rootfsLayoutSpecs = {
    "nodejs-latest" = [
      "/usr/bin/node"
      "/usr/bin/python"
      "/usr/lib/node_modules/typescript/lib"
    ];
    "go-latest" = [
      "/usr/bin/go"
      "/usr/share/go"
    ];
    "rust-latest" = [
      "/usr/bin/rust-analyzer"
    ];
  };
  rootfsLayoutChecks = lib.mapAttrs' (
    name: requiredPaths:
    let
      image = images.${name};
      requireArgs = lib.concatStringsSep " " (
        map (path: "--require ${lib.escapeShellArg path}") requiredPaths
      );
    in
    lib.nameValuePair "rootfs-layout-${imageNameToCheckName name}" (
      pkgs.runCommand "rootfs-layout-${name}" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 ${../tests/ci/check-rootfs-layout.py} ${image.rootfs} ${image.reports} ${name} ${requireArgs}
        touch "$out"
      ''
    )
  ) rootfsLayoutSpecs;

  runtimeToolChecks = {
    runtime-tools =
      pkgs.runCommand "runtime-tools"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.gnugrep
          ];
        }
        ''
          export DEVCONTAINER_FLAKE=${repoRoot}
          export DEVCONTAINER_PROJECTOR=${compiler.runtimePackages."vscode-extension-projector"}
          export DEVCONTAINER_RUNNER=${compiler.runtimePackages."devcontainer-task-runner"}
          export DEVCONTAINER_DEVPKG=${compiler.runtimePackages.devpkg}
          export DEVPKG_NIXPKGS_REF=path:${nixpkgs.outPath}
          bash ${../tests/ci/check-runtime-tools.sh}
          touch "$out"
        '';

    image-tar-fixture =
      pkgs.runCommand "image-tar-fixture"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.gnugrep
            pkgs.python3
          ];
        }
        ''
          bash ${../tests/ci/check-image-tar-fixture.sh} ${repoRoot}
          touch "$out"
        '';
  };

  fixtureFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) (
    builtins.readDir fixturesDir
  );
  fixtureChecks = lib.mapAttrs' (
    name: _:
    let
      fixture = import (fixturesDir + "/${name}") { inherit self; };
      missing = builtins.filter (
        node: !(builtins.hasAttr node fixture.image.graph.nodes)
      ) fixture.expectedNodes;
    in
    lib.nameValuePair "fixture-${lib.replaceStrings [ ".nix" "-" ] [ "" "_" ] name}" (
      assert missing == [ ];
      pkgs.writeText "fixture-${name}.json" (
        builtins.toJSON {
          image = fixture.image.config.devcontainer.image.name;
          expectedNodes = fixture.expectedNodes;
          missing = missing;
        }
      )
    )
  ) fixtureFiles;

  apiEvalImage = compiler.mkImage {
    modules = [
      ../images/nix.nix
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
            environment.variables = {
              API_BOOL = true;
              API_INT = 7;
              API_LIST = [
                "alpha"
                "beta"
              ];
            };
            environment.variableOrigins = {
              API_BOOL = [ "tests.api" ];
              API_INT = [ "tests.api" ];
              API_LIST = [ "tests.api" ];
            };
            environment.etc."api/example.conf".text = "enabled\n";
            environment.shellInit = "export API_SHELL_INIT=1";
            environment.interactiveShellInit = "export API_INTERACTIVE_SHELL_INIT=1";
            time.timeZone = "Etc/UTC";
            security.pki.certificates = [
              ''
                -----BEGIN CERTIFICATE-----
                MIIBszCCAVmgAwIBAgIUQz8yfqvf1WlLxT4cFAbU+qfY8HkwCgYIKoZIzj0EAwIw
                EjEQMA4GA1UEAwwHYXBpLXRlc3QwHhcNMjYwMTAxMDAwMDAwWhcNMjcwMTAxMDAw
                MDAwWjASMRAwDgYDVQQDDAdhcGktdGVzdDBZMBMGByqGSM49AgEGCCqGSM49AwEH
                A0IABCcmQ4j+9v4o0RW1k8NodMVrY5J5CV+2T7goH4YGKkR3T0E6KsH1rPT2fT3F
                q2o2mYhCdgKxS1w7Jm2F3lCjUzBRMB0GA1UdDgQWBBSgRjv0y7r8e3JJE3G+J4N+
                m9V1xjAfBgNVHSMEGDAWgBSgRjv0y7r8e3JJE3G+J4N+m9V1xjAPBgNVHRMBAf8E
                BTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQCyLTHQePo2Uq3rtwzW6mS4mQ2d6YV+
                cAq4oZlIu3mSWAIhAIXm0k8t5h39Ww0lYJXcc7uzb9BCf60ihoNZGwDYs2z4
                -----END CERTIFICATE-----
              ''
            ];
            programs.git = {
              enable = true;
              lfs.enable = true;
              attributes = [ "*.bin filter=lfs diff=lfs merge=lfs -text" ];
              config.init.defaultBranch = "main";
            };
            programs.ssh = {
              enable = true;
              knownHosts.localhost.publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICodexCodexCodexCodexCodexCodexCodexCodexCodex";
              extraConfig = "  StrictHostKeyChecking accept-new";
            };
            programs.direnv.enable = true;
            programs.nix-index.enable = true;
            programs.nix-ld.libraries = [ pkgs.zlib ];
            nix.settings.substituters = [ "https://cache.nixos.org/" ];
          };
        }
      )
    ];
  };
  invalidKnownHostsRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { lib, ... }:
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
  extensionMetadataRequiredRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { lib, ... }:
              {
                config = {
                  devcontainer.image.name = "extension-metadata-required";
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
                    vscode.extensions."redhat.vscode-yaml" = { };
                  };
                };
              }
            )
          ];
        }).profileReport
        null
    )).success;
  duplicateProfileIdRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { lib, pkgs, ... }:
              {
                config = {
                  devcontainer.image.name = "duplicate-profile-id";
                  devcontainer.image.family = lib.mkForce "test";
                  devcontainer.profiles = {
                    "test/first" = {
                      id = "test/duplicate";
                      enable = true;
                      kind = "test";
                      group = "99-fallback";
                      packages = [ pkgs.hello ];
                      priority = 1;
                      stability = "stable";
                      sharing = "single-image";
                      securityClass = "trusted";
                    };
                    "test/second" = {
                      id = "test/duplicate";
                      enable = true;
                      kind = "test";
                      group = "99-fallback";
                      packages = [ pkgs.hello ];
                      priority = 1;
                      stability = "stable";
                      sharing = "single-image";
                      securityClass = "trusted";
                    };
                  };
                };
              }
            )
          ];
        }).profileReport
        null
    )).success;
  missingProfileGroupRejected =
    !(builtins.tryEval (
      builtins.deepSeq
        (compiler.mkImage {
          modules = [
            (
              { lib, pkgs, ... }:
              {
                config = {
                  devcontainer.image.name = "missing-profile-group";
                  devcontainer.image.family = lib.mkForce "test";
                  devcontainer.profiles."test/missing-group" = {
                    enable = true;
                    kind = "test";
                    group = "not-in-layer-order";
                    packages = [ pkgs.hello ];
                    priority = 1;
                    stability = "stable";
                    sharing = "single-image";
                    securityClass = "trusted";
                  };
                };
              }
            )
          ];
        }).profileReport
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
  pythonProfileEvalImage = compiler.mkImage {
    modules = [
      ../images/python.nix
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
  pythonProfile = lib.findFirst (
    profile: profile.id == "language/python"
  ) (throw "language/python profile missing") pythonProfileEvalImage.profileReport.enabledProfiles;
  pythonExtension = lib.findFirst (
    extension: extension.id == "ms-python.python"
  ) (throw "ms-python.python extension missing") pythonProfileEvalImage.vscodeExtensions.extensions;
  profileDefaultOverrideImage = compiler.mkImage {
    modules = [
      ../images/nix.nix
      (
        { lib, ... }:
        {
          config = {
            devcontainer.image = {
              name = lib.mkForce "profile-default-override";
              family = lib.mkForce "test";
              tags = lib.mkForce [ "eval" ];
            };
            devcontainer.profiles."toolset/docker-client".enable = false;
          };
        }
      )
    ];
  };
  apiEvalCheck =
    let
      env = apiEvalImage.env.containerEnv;
      environmentReport = apiEvalImage.environment.report;
      etcPaths = map (entry: entry.path) apiEvalImage.environment.etc;
      shellText = apiEvalImage.shell.profileText + apiEvalImage.shell.bashrcText;
      layerPathsToLink = (builtins.head apiEvalImage.layers.layers).build.pathsToLink;
      extensionIds = apiEvalImage.profileReport.vscode.extensionIds;
      expectedExtensionIds = [
        "esbenp.prettier-vscode"
        "jnoortheen.nix-ide"
        "tamasfe.even-better-toml"
        "redhat.vscode-yaml"
        "shd101wyy.markdown-preview-enhanced"
        "redhat.vscode-xml"
        "samuelcolvin.jinjahtml"
        "ianandhum.protobuf-support"
        "timonwong.shellcheck"
      ];
    in
    assert env.API_BOOL == "1";
    assert env.API_INT == "7";
    assert env.API_LIST == "alpha:beta";
    assert env.TZDIR == "/etc/zoneinfo";
    assert builtins.elem "/etc/api/example.conf" etcPaths;
    assert builtins.elem "/etc/localtime" etcPaths;
    assert builtins.elem "/etc/zoneinfo" etcPaths;
    assert builtins.elem "/etc/ssl/certs/ca-certificates.crt" etcPaths;
    assert builtins.elem "/etc/gitconfig" etcPaths;
    assert builtins.elem "/etc/gitattributes" etcPaths;
    assert builtins.elem "/etc/ssh/ssh_config" etcPaths;
    assert builtins.elem "/etc/ssh/ssh_known_hosts" etcPaths;
    assert builtins.elem "/etc/direnv/direnvrc" etcPaths;
    assert builtins.elem "/etc/nix/nix.conf" etcPaths;
    assert builtins.elem "man" environmentReport.extraOutputsToInstall;
    assert builtins.elem "/man" layerPathsToLink;
    assert builtins.length extensionIds == builtins.length expectedExtensionIds;
    assert lib.all (id: builtins.elem id extensionIds) expectedExtensionIds;
    assert lib.hasInfix "API_SHELL_INIT" shellText;
    assert lib.hasInfix "API_INTERACTIVE_SHELL_INIT" shellText;
    assert apiEvalImage.fhsRuntime.dynamicLoaderMode == "nix-ld";
    assert builtins.match ".*zlib.*" env.NIX_LD_LIBRARY_PATH != null;
    assert invalidKnownHostsRejected;
    assert unsupportedSudoRejected;
    assert extensionMetadataRequiredRejected;
    assert duplicateProfileIdRejected;
    assert missingProfileGroupRejected;
    assert missingCompanionToolRejected;
    assert !(builtins.hasAttr "toolset/docker-client" profileDefaultOverrideImage.graph.nodes);
    pkgs.writeText "api-eval-check.json" (
      builtins.toJSON {
        environment = environmentReport;
        etcPaths = etcPaths;
        invalidKnownHostsRejected = invalidKnownHostsRejected;
        unsupportedSudoRejected = unsupportedSudoRejected;
        extensionMetadataRequiredRejected = extensionMetadataRequiredRejected;
        duplicateProfileIdRejected = duplicateProfileIdRejected;
        missingProfileGroupRejected = missingProfileGroupRejected;
        missingCompanionToolRejected = missingCompanionToolRejected;
        profileDefaultOverrideNodes = builtins.attrNames profileDefaultOverrideImage.graph.nodes;
      }
    );
  profileEvalCheck =
    assert builtins.elem "uv" pythonProfile.packages;
    assert pythonProfile.vscode.settings."python.defaultInterpreterPath" == "/usr/bin/python";
    assert builtins.elem "ms-python.python" pythonProfileEvalImage.profileReport.vscode.extensionIds;
    assert builtins.elem "python-version" pythonProfile.tests.smoke;
    assert builtins.hasAttr "language/python" pythonProfileEvalImage.graph.nodes;
    assert pythonExtension.native;
    assert pythonExtension.bucket == "82-vscode-extensions-python";
    assert builtins.elem "python" pythonExtension.companionTools;
    assert builtins.elem "language/python" pythonExtension.origins;
    assert pythonProfileEvalImage.profileReport.validation.companionToolsProvidedByNix;
    pkgs.writeText "profile-eval-check.json" (
      builtins.toJSON {
        profile = pythonProfile;
        extension = pythonExtension;
      }
    );
in
reportChecks
// reportCliChecks
// imageBuildChecks
// rootfsLayoutChecks
// runtimeToolChecks
// fixtureChecks
// {
  api-eval = apiEvalCheck;
  profile-eval = profileEvalCheck;
}
