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
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [ cfg.package ];
        environment.etc."gitconfig".text = gitConfigText;
      }

      (lib.mkIf (attributesText != "") {
        environment.etc."gitattributes".text = attributesText;
      })

      (lib.mkIf cfg.prompt.enable {
        environment.etc."profile.d/git-prompt.sh".text = promptHook;
      })

      {
        devcontainer.tests.smoke = [
          {
            name = "git-system-config";
            command = [
              "bash"
              "-lc"
              "test -r /etc/gitconfig && git config --system --list >/dev/null"
            ];
          }
        ];
      }
    ]
  );
}
