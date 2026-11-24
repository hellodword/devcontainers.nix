# Python 3 runtime, uv, pipx, formatters, typecheckers, linters, and UV/PYTHON environment.
{ pkgs }:
let
  usrPackages = [
    pkgs.python3
    pkgs.python3Packages.pip
    pkgs.uv
    pkgs.pipx
    pkgs.python3Packages.ruff
    pkgs.python3Packages.mypy
    pkgs.python3Packages.pytest
    pkgs.python3Packages.ipython
    pkgs.python3Packages.black
    pkgs.python3Packages.pylint
    pkgs.python3Packages.bandit
  ];
  cacheEnv = {
    PIP_CACHE_DIR = "/home/vscode/.cache/pip";
    PYTHONUSERBASE = "/home/vscode/.local/share/python";
    PYTHONPYCACHEPREFIX = "/home/vscode/.cache/python";
    MYPY_CACHE_DIR = "/home/vscode/.cache/mypy";
    UV_CACHE_DIR = "/home/vscode/.cache/uv";
    UV_TOOL_DIR = "/home/vscode/.local/share/uv/tools";
    UV_TOOL_BIN_DIR = "/home/vscode/.local/share/uv/bin";
    UV_LINK_MODE = "copy";
  };
  devEnv = { };
in
{
  inherit usrPackages cacheEnv devEnv;
  storeDeps = usrPackages;
  pathSegments = [
    "/home/vscode/.local/share/uv/bin"
    "/home/vscode/.local/share/python/bin"
  ];
  env = cacheEnv // devEnv;
}
