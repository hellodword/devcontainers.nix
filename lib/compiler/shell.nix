{ pkgs, lib }:
{
  config,
  compiledEnvironment ? {
    shellAliases = { };
    shellAliasOrigins = { };
    shellInit = "";
    interactiveShellInit = "";
  },
  compiledEnv ? {
    containerEnv = { };
  },
}:
let
  cfg = config.programs.bash;
  locale = config.i18n;
  pathString = path: builtins.unsafeDiscardStringContext (toString path);
  invalidAliasNames = builtins.filter (name: builtins.match "[A-Za-z0-9_.+-]+" name == null) (
    builtins.attrNames compiledEnvironment.shellAliases
  );
  aliases =
    if invalidAliasNames != [ ] then
      throw (
        "environment.shellAliases contains invalid alias names: "
        + lib.concatStringsSep ", " invalidAliasNames
        + ". Alias names may only contain letters, numbers, '_', '-', '.', and '+'."
      )
    else
      compiledEnvironment.shellAliases;
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
  sortedEnvNames = lib.sort lib.lessThan (builtins.attrNames compiledEnv.containerEnv);
  renderExport =
    name:
    let
      value = builtins.getAttr name compiledEnv.containerEnv;
    in
    "export ${name}=${lib.escapeShellArg value}";
  environmentExportText =
    if sortedEnvNames != [ ] then
      lib.concatStringsSep "\n" ((map renderExport sortedEnvNames) ++ [ "" ])
    else
      "";
  shellInitText = lib.optionalString (compiledEnvironment.shellInit != "") ''
    ${compiledEnvironment.shellInit}
  '';
  interactiveShellInitText = lib.optionalString (compiledEnvironment.interactiveShellInit != "") ''
    ${compiledEnvironment.interactiveShellInit}
  '';

  promptText = lib.optionalString (cfg.enable && cfg.prompt.enable) ''
    PROMPT_DIRTRIM=3
    if [ -t 1 ]; then
      PS1='\[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '
    else
      PS1='\u@\h:\w\$ '
    fi
  '';

  historyText = lib.optionalString (cfg.enable && cfg.history.enable) ''
    HISTFILE="''${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
    HISTSIZE=50000
    HISTFILESIZE=100000
    HISTCONTROL=ignoreboth:erasedups
    shopt -s histappend
    shopt -s checkwinsize
  '';

  completionText = lib.optionalString (cfg.enable && cfg.completion.enable) ''
    if ! declare -F _init_completion >/dev/null 2>&1 && [ -r /share/bash-completion/bash_completion ]; then
      . /share/bash-completion/bash_completion
    fi
  '';

  commandNotFoundText = lib.optionalString (cfg.enable && cfg.commandNotFound.enable) ''
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
    ${environmentExportText}
    ${shellInitText}

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
  + environmentExportText
  + aliasesText
  + promptText
  + historyText
  + completionText
  + commandNotFoundText
  + interactiveShellInitText;

  imagePaths = [
    locale.glibcLocales
  ]
  ++ lib.optionals (cfg.enable && cfg.completion.enable) [ pkgs.bash-completion ];
  aliasReport = lib.genAttrs sortedAliasNames (name: {
    command = builtins.getAttr name aliases;
    origins = compiledEnvironment.shellAliasOrigins.${name} or [ ];
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
      enabled = true;
      lang = locale.defaultLocale;
      language = locale.language;
      lc = locale.extraLocaleSettings;
      lcAll = null;
      archive = {
        enabled = true;
        package = locale.glibcLocales.pname or locale.glibcLocales.name or "<unknown>";
        path = "${locale.glibcLocales}/lib/locale/locale-archive";
      };
    };
    aliases = aliasReport;
    bash = {
      prompt = cfg.prompt.enable;
      history = cfg.history.enable;
      completion = cfg.completion.enable;
      commandNotFound = cfg.commandNotFound.enable;
    };
    generatedFiles = generatedFiles;
    imagePaths = map pathString imagePaths;
    commandNotFound = {
      enabled = cfg.enable && cfg.commandNotFound.enable;
      database = "nix-index-database";
      autoInstall = false;
    };
  };
}
