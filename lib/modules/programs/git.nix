{ lib, config, ... }:
let
  cfg = config.programs.git;
  renderValue =
    value: if builtins.isBool value then if value then "true" else "false" else toString value;
  renderSection =
    section: values:
    let
      lines = lib.mapAttrsToList (name: value: "\t${name} = ${renderValue value}") values;
    in
    lib.optionalString (lines != [ ]) ("[${section}]\n" + lib.concatStringsSep "\n" lines);
  renderedConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList renderSection cfg.config);
  lfsConfig = lib.optionalString cfg.lfs.enable ''
    [filter "lfs"]
    	clean = git-lfs clean -- %f
    	smudge = git-lfs smudge -- %f
    	process = git-lfs filter-process
    	required = true
  '';
  attributesText = lib.concatStringsSep "\n" (
    cfg.attributes ++ lib.optional (cfg.extraAttributes != "") cfg.extraAttributes ++ [ "" ]
  );
  gitConfigText = lib.concatStringsSep "\n" (
    builtins.filter (part: part != "") [
      renderedConfig
      lfsConfig
      cfg.extraConfig
      ""
    ]
  );
  promptHook = ''
    if [ -r ${cfg.package}/share/git/contrib/completion/git-prompt.sh ]; then
      . ${cfg.package}/share/git/contrib/completion/git-prompt.sh
      export GIT_PS1_SHOWDIRTYSTATE=1
      export GIT_PS1_SHOWUNTRACKEDFILES=1
    fi
  '';
  completionHook =
    lib.optionalString (config.programs.bash.enable && config.programs.bash.completion.enable)
      ''
        if ! complete -p git >/dev/null 2>&1 && [ -r ${cfg.package}/share/bash-completion/completions/git ]; then
          . ${cfg.package}/share/bash-completion/completions/git
        fi
      '';
  vscodeGitEditorHook = ''
    if [ -z "$(${cfg.package}/bin/git config --get core.editor)" ] && [ -z "''${GIT_EDITOR:-}" ]; then
      if [ "''${TERM_PROGRAM:-}" = "vscode" ]; then
        if command -v code-insiders >/dev/null 2>&1 && ! command -v code >/dev/null 2>&1; then
          export GIT_EDITOR="code-insiders --wait"
        else
          export GIT_EDITOR="code --wait"
        fi
      fi
    fi
  '';
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.etc."gitconfig".text = gitConfigText;
        environment.interactiveShellInit = completionHook + vscodeGitEditorHook;
      }

      (lib.mkIf (attributesText != "") {
        environment.etc."gitattributes".text = attributesText;
      })

      (lib.mkIf cfg.prompt.enable {
        environment.etc."profile.d/git-prompt.sh".text = promptHook;
      })
    ]
  );
}
