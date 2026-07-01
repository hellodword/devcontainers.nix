{ ... }:
{
  config.devcontainer.profiles."editor/core" = {
    kind = "editor";
    group = "vscode-extensions-base";
    packages = [ ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";

    vscode.settings = {
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
      "terminal.integrated.suggest.enabled" = false;
      "telemetry.feedback.enabled" = false;
      "telemetry.editStats.details.enabled" = false;
      "telemetry.editStats.enabled" = false;
      "telemetry.editStats.showDecorations" = false;
      "telemetry.editStats.showStatusBar" = false;

      "json.schemaDownload.trustedDomains" = {
        "https://developer.microsoft.com/json-schemas/" = true;
        "https://json-schema.org/" = true;
        "https://json.schemastore.org/" = true;
        "https://raw.githubusercontent.com/" = true;
        "https://schemastore.azurewebsites.net/" = true;
        "https://www.schemastore.org/" = true;
      };
    };
  };
}
