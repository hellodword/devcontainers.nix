{ ... }:
{
  config.devcontainer.profiles."editor/markdown-preview" = {
    kind = "editor";
    group = "80-vscode-extensions-base";
    packages = [ ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";

    vscode = {
      extensions."shd101wyy.markdown-preview-enhanced" = {
        native = false;
        bucket = "80-vscode-extensions-base";
        companionTools = [ ];
      };
      settings."markdown-preview-enhanced.liveUpdate" = false;
    };
  };
}
