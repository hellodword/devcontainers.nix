{ ... }:
{
  config.devcontainer.profiles."editor/markdown-preview" = {
    kind = "editor";
    group = "vscode-extensions-base";
    packages = [ ];
    priority = 80;
    stability = "stable";
    sharing = "global";
    securityClass = "trusted";

    vscode = {
      extensions."shd101wyy.markdown-preview-enhanced" = {
        native = false;
        bucket = "vscode-extensions-base";
        companionTools = [ ];
      };
      settings."markdown-preview-enhanced.liveUpdate" = false;
    };
  };
}
