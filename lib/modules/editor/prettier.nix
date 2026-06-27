{ pkgs, ... }:
{
  config.devcontainer.profiles."editor/prettier" = {
    kind = "editor";
    group = "07-workflow-format-tools";
    packages = [ pkgs.prettier ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";
    provides.commands = [ "prettier" ];

    vscode = {
      extensions."esbenp.prettier-vscode" = {
        native = false;
        bucket = "80-vscode-extensions-base";
        companionTools = [ "prettier" ];
      };
      settings = {
        "json.format.enable" = false;
        "prettier.enable" = true;
        # Failed to load module. If you have prettier or plugins referenced in package.json, ensure you have run `npm install` /usr/bin/package.json
        # "prettier.prettierPath" = "/usr/bin/prettier";
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
      };
    };
  };
}
