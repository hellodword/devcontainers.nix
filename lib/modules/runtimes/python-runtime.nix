{
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.runtimes.python;
  python = if cfg.package == null then pkgs.python3 else cfg.package;
  packages = [ python ];
in
{
  config.devcontainer.profiles."runtime/python" = {
    kind = "runtime";
    group = "30-python-runtime";
    packages = packages;
    priority = 85;
    stability = "stable";
    sharing = "cross-language";
    securityClass = "trusted";
    provides.commands = [
      "python"
      "python3"
    ];
    env = {
      variables = {
        PYTHONUSERBASE = "$XDG_DATA_HOME/python";
        PYTHONPYCACHEPREFIX = "$XDG_CACHE_HOME/python";
        PYTHON_EGG_CACHE = "$XDG_CACHE_HOME/python-eggs";
        MYPY_CACHE_DIR = "$XDG_CACHE_HOME/mypy";
        JUPYTER_CONFIG_DIR = "$XDG_CONFIG_HOME/jupyter";
        JUPYTER_PLATFORM_DIRS = "1";
        UV_CACHE_DIR = "$XDG_CACHE_HOME/uv";
        UV_TOOL_DIR = "$XDG_DATA_HOME/uv/tools";
        UV_TOOL_BIN_DIR = "$XDG_DATA_HOME/uv/bin";
        UV_LINK_MODE = "copy";
      };
      path = [
        "$UV_TOOL_BIN_DIR"
        "$PYTHONUSERBASE/bin"
      ];
    };
  };
}
