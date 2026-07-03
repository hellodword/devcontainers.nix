{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.devcontainer.runtimes.python;
  python = if cfg.package == null then pkgs.python3 else cfg.package;
  packages = [
    python
    python.pkgs.pip
    pkgs.uv
  ];
in
{
  options.devcontainer.runtimes.python.package = mkOption {
    type = types.nullOr types.package;
    default = null;
  };

  config.devcontainer = {
    layers.bucketDefinitions."python-runtime" = {
      order = 21000;
      owner = "runtimes/python-runtime";
      purpose = "Python interpreter, package installer, and uv runtime tools.";
    };

    profiles."runtime/python" = {
      kind = "runtime";
      group = "python-runtime";
      packages = packages;
      priority = 85;
      stability = "stable";
      sharing = "cross-language";
      securityClass = "trusted";
      provides.commands = [
        "python"
        "python3"
        "pip"
        "pip3"
        "uv"
        "uvx"
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
      tests.cases."runtime.python" = {
        tags = [
          "smoke"
          "runtime"
          "python"
        ];
        scripts = [
          {
            shell = "bash";
            interactive = false;
            command = ''
              set -e
              python --version
              python3 --version
              pip --version
              pip3 --version
              uv --version
              uvx --version
              python -c 'import ssl, sqlite3, ctypes'
            '';
          }
        ];
      };
    };
  };
}
