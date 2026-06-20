{ ... }:
{
  config.devcontainer.vscode = {
    extensions = [
      "esbenp.prettier-vscode"
      "redhat.vscode-yaml"
      "shd101wyy.markdown-preview-enhanced"
      "redhat.vscode-xml"
      "tamasfe.even-better-toml"
      "samuelcolvin.jinjahtml"
      "ianandhum.protobuf-support"
      "timonwong.shellcheck"
    ];

    settings = {
      "diffEditor.wordWrap" = "on";
      "editor.formatOnSave" = true;
      "editor.formatOnType" = false;
      "editor.wordWrap" = "on";
      "workbench.localHistory.enabled" = false;
      "remote.autoForwardPortsSource" = "hybrid";
      "editor.tabSize" = 2;
      "extensions.ignoreRecommendations" = true;
      "files.eol" = "\n";
      "files.associations" = {
        "**/.env.*" = "properties";
        "**/flake.lock" = "json";
        "*.arb" = "json";
      };
      "github.gitAuthentication" = false;
      "github.branchProtection" = false;
      "github.showAvatar" = false;
      "git.enabled" = true;
      "git.enableSmartCommit" = false;
      "git.enableCommitSigning" = false;
      "git.enableStatusBarSync" = false;
      "git.openRepositoryInParentFolders" = "always";
      "json.format.enable" = false;
      "prettier.enable" = true;
      "[json]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[jsonc]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[markdown]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[javascript]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[typescript]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[html]" = {
        "editor.defaultFormatter" = "esbenp.prettier-vscode";
      };
      "[yaml]" = {
        "editor.defaultFormatter" = "redhat.vscode-yaml";
      };
      "redhat.telemetry.enabled" = false;
      "yaml.schemaStore.enable" = true;
      "yaml.format.enable" = true;
      "yaml.completion" = true;
      "markdown-preview-enhanced.liveUpdate" = false;
      "xml.format.enabled" = true;
      "[toml]" = {
        "editor.defaultFormatter" = "tamasfe.even-better-toml";
      };
      "evenBetterToml.formatter.crlf" = false;
      "protobuf-support.protols.path" = "/usr/bin/protols";
      "shellcheck.enable" = true;
      "shellcheck.enableQuickFix" = true;
      "shellcheck.run" = "onSave";
      "shellcheck.executablePath" = "/usr/bin/shellcheck";
      "shellcheck.exclude" = [ ];
      "shellcheck.customArgs" = [ ];
      "shellcheck.ignorePatterns" = {
        "**/*.csh" = true;
        "**/*.cshrc" = true;
        "**/*.fish" = true;
        "**/*.login" = true;
        "**/*.logout" = true;
        "**/*.tcsh" = true;
        "**/*.tcshrc" = true;
        "**/*.xonshrc" = true;
        "**/*.xsh" = true;
        "**/*.zsh" = true;
        "**/*.zshrc" = true;
        "**/zshrc" = true;
        "**/*.zprofile" = true;
        "**/zprofile" = true;
        "**/*.zlogin" = true;
        "**/zlogin" = true;
        "**/*.zlogout" = true;
        "**/zlogout" = true;
        "**/*.zshenv" = true;
        "**/zshenv" = true;
        "**/*.zsh-theme" = true;
      };
      "shellcheck.disableVersionCheck" = true;
      "shellcheck.logLevel" = "debug";
      "chat.agent.enabled" = false;
      "chat.edits2.enabled" = false;
      "chat.commandCenter.enabled" = false;
      "chat.mcp.discovery.enabled" = {
        "claude-desktop" = false;
        "windsurf" = false;
        "cursor-global" = false;
        "cursor-workspace" = false;
      };
      "chat.extensionTools.enabled" = false;
      "chat.implicitContext.enabled" = {
        "panel" = "never";
        "editing-session" = "never";
      };
      "chat.detectParticipant.enabled" = false;
      "chat.mcp.access" = "none";
      "chat.disableAIFeatures" = true;
      "inlineChat.enableV2" = false;
    };
  };
}
