{ pkgs, lib }:
{ config }:
let
  cfg = config.devcontainer.shell;
  locale = config.devcontainer.locale;
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  invalidAliasNames = builtins.filter (name: builtins.match "[A-Za-z0-9_.+-]+" name == null) (
    builtins.attrNames cfg.aliases
  );
  invalidLcNames = builtins.filter (
    name: name == "LC_ALL" || builtins.match "LC_[A-Z_]+" name == null
  ) (builtins.attrNames locale.lc);
  validatedLocale =
    if invalidLcNames != [ ] then
      throw (
        "devcontainer.locale.lc keys must be LC_* variables other than LC_ALL; invalid keys: "
        + lib.concatStringsSep ", " invalidLcNames
      )
    else
      locale;
  aliases =
    if invalidAliasNames != [ ] then
      throw (
        "devcontainer.shell.aliases contains invalid alias names: "
        + lib.concatStringsSep ", " invalidAliasNames
        + ". Alias names may only contain letters, numbers, '_', '-', '.', and '+'."
      )
    else
      cfg.aliases;
  sortedAliasNames = lib.sort lib.lessThan (builtins.attrNames aliases);
  renderAlias =
    name:
    let
      value = builtins.getAttr name aliases;
    in
    "alias ${name}=${lib.escapeShellArg value}";
  aliasLines = map renderAlias sortedAliasNames;
  aliasesText =
    if cfg.enable && aliasLines != [ ] then lib.concatStringsSep "\n" (aliasLines ++ [ "" ]) else "";

  promptText = lib.optionalString (cfg.enable && cfg.bash.prompt.enable) ''
    PROMPT_DIRTRIM=3
    if [ -t 1 ]; then
      PS1='\[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '
    else
      PS1='\u@\h:\w\$ '
    fi
  '';

  historyText = lib.optionalString (cfg.enable && cfg.bash.history.enable) ''
    HISTFILE="''${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
    HISTSIZE=50000
    HISTFILESIZE=100000
    HISTCONTROL=ignoreboth:erasedups
    shopt -s histappend
    shopt -s checkwinsize
  '';

  completionText = lib.optionalString (cfg.enable && cfg.bash.completion.enable) ''
    if ! declare -F _init_completion >/dev/null 2>&1 && [ -r /share/bash-completion/bash_completion ]; then
      . /share/bash-completion/bash_completion
    fi
  '';

  commandNotFoundText = lib.optionalString (cfg.enable && cfg.bash.commandNotFound.enable) ''
    command_not_found_handle() {
      local command="$1"
      shift || true
      if command -v nix-locate >/dev/null 2>&1; then
        printf '%s: command not found\n' "$command" >&2
        nix-locate --minimal --whole-name --at-root "/bin/$command" 2>/dev/null | head -n 20 >&2 || true
      else
        printf '%s: command not found\n' "$command" >&2
      fi
      return 127
    }
  '';

  profileText = ''
    # System profile for devcontainers.nix images.
    if [ -d /etc/profile.d ]; then
      for script in /etc/profile.d/*.sh; do
        [ -e "$script" ] || continue
        [ -r "$script" ] && . "$script"
      done
      unset script
    fi

    case "$-" in
      *i*)
        if [ -n "''${BASH_VERSION:-}" ] && [ -r /etc/bashrc ]; then
          . /etc/bashrc
        fi
        ;;
    esac
  '';

  bashrcText = ''
    # System bashrc for devcontainers.nix images.
    if [ -z "''${BASH_VERSION:-}" ]; then
      return 0 2>/dev/null || exit 0
    fi

    case "$-" in
      *i*) ;;
      *) return 0 2>/dev/null || exit 0 ;;
    esac

  ''
  + aliasesText
  + promptText
  + historyText
  + completionText
  + commandNotFoundText;

  imagePaths =
    lib.optionals (validatedLocale.enable && validatedLocale.archive.enable) [
      validatedLocale.archive.package
    ]
    ++ lib.optionals (cfg.enable && cfg.bash.completion.enable) [ pkgs.bash-completion ];
  aliasReport = lib.genAttrs sortedAliasNames (name: {
    command = builtins.getAttr name aliases;
    origins = cfg.aliasOrigins.${name} or [ ];
  });
  generatedFiles = [
    "/etc/profile"
    "/etc/bashrc"
    "/etc/bash.bashrc"
  ];
in
{
  inherit
    profileText
    bashrcText
    generatedFiles
    imagePaths
    ;
  bashBashrcText = bashrcText;
  commandNotFoundHook = commandNotFoundText;
  report = {
    enabled = cfg.enable;
    locale = {
      enabled = validatedLocale.enable;
      lang = validatedLocale.lang;
      language = validatedLocale.language;
      lc = validatedLocale.lc;
      lcAll = validatedLocale.lcAll;
      archive = {
        enabled = validatedLocale.archive.enable;
        package =
          validatedLocale.archive.package.pname or validatedLocale.archive.package.name or "<unknown>";
        path = lib.optionalString validatedLocale.archive.enable "${validatedLocale.archive.package}/lib/locale/locale-archive";
      };
    };
    aliases = aliasReport;
    bash = {
      prompt = cfg.bash.prompt.enable;
      history = cfg.bash.history.enable;
      completion = cfg.bash.completion.enable;
      commandNotFound = cfg.bash.commandNotFound.enable;
    };
    generatedFiles = generatedFiles;
    imagePaths = map pathString imagePaths;
    commandNotFound = {
      enabled = cfg.enable && cfg.bash.commandNotFound.enable;
      database = "nix-index-database";
      autoInstall = false;
    };
  };
}
