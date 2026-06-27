{ pkgs, ... }:
{
  config.devcontainer.profiles."editor/shellcheck" = {
    kind = "editor";
    group = "07-workflow-format-tools";
    packages = [ pkgs.shellcheck ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "shellcheck" ];

    vscode = {
      extensions."timonwong.shellcheck" = {
        native = false;
        bucket = "80-vscode-extensions-base";
        companionTools = [ "shellcheck" ];
      };
      settings = {
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
      };
    };
  };
}
