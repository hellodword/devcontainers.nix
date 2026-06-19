{ lib, pkgs, config, ... }:
let
  packages = [ pkgs.python313 ];
in
{
  config = lib.mkIf config.devcontainer.runtimes.python.enable {
    devcontainer.packages = packages;
    devcontainer.env.container = {
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
    devcontainer.env.origins.container = {
      PYTHONUSERBASE = [ "runtimes.python" ];
      PYTHONPYCACHEPREFIX = [ "runtimes.python" ];
      PYTHON_EGG_CACHE = [ "runtimes.python" ];
      MYPY_CACHE_DIR = [ "runtimes.python" ];
      JUPYTER_CONFIG_DIR = [ "runtimes.python" ];
      JUPYTER_PLATFORM_DIRS = [ "runtimes.python" ];
      UV_CACHE_DIR = [ "runtimes.python" ];
      UV_TOOL_DIR = [ "runtimes.python" ];
      UV_TOOL_BIN_DIR = [ "runtimes.python" ];
      UV_LINK_MODE = [ "runtimes.python" ];
    };
    devcontainer.path.segments.language = [ "$UV_TOOL_BIN_DIR" "$PYTHONUSERBASE/bin" ];
    devcontainer.path.segmentOrigins.language = {
      "$UV_TOOL_BIN_DIR" = [ "runtimes.python" ];
      "$PYTHONUSERBASE/bin" = [ "runtimes.python" ];
    };
    devcontainer.graph.nodes."runtime/python" = {
      kind = "runtime";
      group = "30-python-runtime";
      paths = packages;
      stability = "stable";
      sharing = "cross-language";
      priority = 85;
      securityClass = "trusted";
    };
  };
}
