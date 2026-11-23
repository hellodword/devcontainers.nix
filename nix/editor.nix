# Offline VS Code extensions, projection index, read-only Machine settings, and Dev Container metadata for :latest.
{
  pkgs,
  lib,
}:
let
  ossExtensionIds = [
    "editorconfig.editorconfig"
    "shd101wyy.markdown-preview-enhanced"
    "esbenp.prettier-vscode"
    "timonwong.shellcheck"
    "nefrob.vscode-just-syntax"
    "tamasfe.even-better-toml"
    "redhat.vscode-yaml"
    "redhat.vscode-xml"
    "samuelcolvin.jinjahtml"
    "drblury.protobuf-vsc"
    "jnoortheen.nix-ide"
    "golang.go"
    "rust-lang.rust-analyzer"
    "ms-python.python"
    "ms-python.debugpy"
    "ms-python.vscode-python-envs"
    "charliermarsh.ruff"
    "ms-python.mypy-type-checker"
    "ms-python.pylint"
    "ms-python.black-formatter"
    "dbaeumer.vscode-eslint"
    "vue.volar"
    "bradlc.vscode-tailwindcss"
    "stylelint.vscode-stylelint"
    "yoavbls.pretty-ts-errors"
  ];

  restrictedExtensionIds = [
    "ms-python.vscode-pylance"
  ];

  resolveExtension =
    id:
    let
      parts = lib.splitString "." (lib.toLower id);
      publisher = builtins.head parts;
      name = lib.concatStringsSep "." (builtins.tail parts);
      pkg =
        pkgs.vscode-marketplace-release.${publisher}.${name} or pkgs.open-vsx-release.${publisher}.${name}
          or (throw "VS Code extension ${id} not found in nix-vscode-extensions");
      uniqueId = pkg.vscodeExtUniqueId or id;
    in
    {
      inherit id pkg uniqueId;
      storeSubdir = "${pkg}/share/vscode/extensions/${uniqueId}";
    };

  ossExtensions = map resolveExtension ossExtensionIds;
  restrictedExtensions = map resolveExtension restrictedExtensionIds;
  allExtensions = ossExtensions ++ restrictedExtensions;

  projectionTargets = [
    "/home/vscode/.vscode-server/extensions"
    "/home/vscode/.vscode-server-insiders/extensions"
    "/home/vscode/.vscode-remote/extensions"
  ];

  extensionStorePaths = map (ext: ext.storeSubdir) allExtensions;

  machineSettings = {
    "diffEditor.wordWrap" = "on";
    "editor.formatOnSave" = true;
    "editor.formatOnType" = false;
    "editor.wordWrap" = "on";
    "editor.tabSize" = 2;
    "files.eol" = "\n";
    "files.associations" = {
      "**/.env.*" = "properties";
      "**/flake.lock" = "json";
    };
    "workbench.localHistory.enabled" = false;
    "remote.autoForwardPortsSource" = "hybrid";
    "extensions.autoCheckUpdates" = false;
    "extensions.autoUpdate" = false;
    "extensions.ignoreRecommendations" = true;
    "update.mode" = "none";

    "github.gitAuthentication" = false;
    "github.branchProtection" = false;
    "github.showAvatar" = false;
    "git.enabled" = true;
    "git.enableSmartCommit" = false;
    "git.enableCommitSigning" = false;
    "git.enableStatusBarSync" = false;
    "git.openRepositoryInParentFolders" = "always";

    "chat.agent.enabled" = false;
    "chat.edits2.enabled" = false;
    "chat.commandCenter.enabled" = false;
    "chat.extensionTools.enabled" = false;
    "chat.detectParticipant.enabled" = false;
    "chat.mcp.access" = "none";
    "chat.disableAIFeatures" = true;
    "inlineChat.enableV2" = false;
    "terminal.integrated.suggest.enabled" = false;

    "telemetry.enableTelemetry" = false;
    "telemetry.feedback.enabled" = false;
    "telemetry.editStats.details.enabled" = false;
    "telemetry.editStats.enabled" = false;
    "telemetry.editStats.showDecorations" = false;
    "telemetry.editStats.showStatusBar" = false;
    "telemetry.telemetryLevel" = "off";

    "rust-analyzer.server.path" = "/usr/bin/rust-analyzer";
    "rust-analyzer.check.command" = "clippy";

    "go.toolsManagement.checkForUpdates" = "off";
    "go.toolsManagement.autoUpdate" = false;
    "go.gopath" = "/home/vscode/.local/share/go";
    "go.goroot" = "/usr/share/go";

    "nix.enableLanguageServer" = true;
    "nix.serverPath" = "/usr/bin/nixd";
    "nix.formatterPath" = "nixfmt";
    "nix.serverSettings" = {
      nixd = {
        formatting = {
          command = [ "nixfmt" ];
        };
      };
    };

    "python.defaultInterpreterPath" = "/usr/bin/python";
    "[python]" = {
      "editor.defaultFormatter" = "charliermarsh.ruff";
    };
    "ruff.nativeServer" = "on";
    "ruff.path" = [ "/usr/bin/ruff" ];
    "python-envs.alwaysUseUv" = true;
    "mypy-type-checker.importStrategy" = "fromEnvironment";
    "mypy-type-checker.path" = [ "/usr/bin/mypy" ];
    "pylint.importStrategy" = "fromEnvironment";
    "pylint.path" = [ "/usr/bin/pylint" ];
    "black-formatter.importStrategy" = "fromEnvironment";
    "black-formatter.path" = [ "/usr/bin/black" ];

    "typescript.tsdk" = "/usr/lib/node_modules/typescript/lib";
    "eslint.workingDirectories" = [ { mode = "auto"; } ];
    "eslint.runtime" = "/usr/bin/node";
    "vue.server.path" = "/usr/bin/vue-language-server";
    "stylelint.runtime" = "/usr/bin/node";
    "stylelint.stylelintPath" = "/usr/lib/node_modules/stylelint";

    "shellcheck.enable" = true;
    "shellcheck.enableQuickFix" = true;
    "shellcheck.run" = "onSave";
    "shellcheck.executablePath" = "/usr/bin/shellcheck";
    "shellcheck.disableVersionCheck" = true;

    "vscode-just.justPath" = "/usr/bin/just";
    "vscode-just.lspPath" = "/usr/bin/just-lsp";

    "[toml]" = {
      "editor.defaultFormatter" = "tamasfe.even-better-toml";
    };
    "evenBetterToml.formatter.crlf" = false;
    "evenBetterToml.taplo.path" = "/usr/bin/taplo";

    "[yaml]" = {
      "editor.defaultFormatter" = "redhat.vscode-yaml";
    };
    "redhat.telemetry.enabled" = false;
    "yaml.schemaStore.enable" = true;
    "yaml.format.enable" = true;
    "yaml.completion" = true;

    "xml.format.enabled" = true;
    "xml.server.preferBinary" = true;

    "json.format.enable" = false;
    "prettier.enable" = true;

    "[proto]" = {
      "editor.defaultFormatter" = "DrBlury.protobuf-vsc";
    };
    "protobuf.formatter.enabled" = true;
    "protobuf.protoc.path" = "/usr/bin/protoc";
    "protobuf.grpcurl.path" = "/usr/bin/grpcurl";
    "protobuf.externalLinter.protolintPath" = "/usr/bin/protolint";
    "protobuf.externalLinter.apiLinterPath" = "/usr/bin/api-linter";
    "protobuf.externalLinter.linter" = "buf";
    "protobuf.externalLinter.enabled" = true;
    "protobuf.externalLinter.bufPath" = "/usr/bin/buf";
    "protobuf.buf.useManaged" = false;
    "protobuf.buf.path" = "/usr/bin/buf";
    "protobuf.autoDetection.enabled" = false;
  };

  machineSettingsJson = builtins.toJSON machineSettings + "\n";

  serverRoots = [
    "/home/vscode/.vscode-server"
    "/home/vscode/.vscode-server-insiders"
    "/home/vscode/.vscode-remote"
  ];

  devcontainerMetadata = [
    {
      init = true;
      overrideCommand = true;
      remoteUser = "vscode";
      containerUser = "vscode";
      updateRemoteUserUID = false;
      privileged = false;
      capAdd = [ ];
      securityOpt = [ "label=disable" ];
      userEnvProbe = "loginInteractiveShell";
      mounts = [
        "source=\${localWorkspaceFolder}/.devcontainer,target=/workspaces/\${localWorkspaceFolderBasename}/.devcontainer,type=bind,readonly"
      ];
      postCreateCommand = {
        devcontainer-tasks = "devcontainer-task-runner run postCreate";
      };
      postStartCommand = {
        devcontainer-tasks = "devcontainer-task-runner run postStart";
      };
    }
  ];
in
{
  ossPackages = map (ext: ext.pkg) ossExtensions;
  restrictedPackages = map (ext: ext.pkg) restrictedExtensions;
  allPackages = map (ext: ext.pkg) allExtensions;
  extensionIds = map (ext: ext.id) allExtensions;
  inherit
    projectionTargets
    extensionStorePaths
    machineSettings
    machineSettingsJson
    serverRoots
    devcontainerMetadata
    ;
}
