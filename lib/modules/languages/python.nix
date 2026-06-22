{
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.languages.python;
  pythonPackages = if cfg.packageSet == null then pkgs.python3Packages else cfg.packageSet;
  packages = [
    pkgs.uv
    pkgs.pipx
    pythonPackages.ruff
    pythonPackages.mypy
    pythonPackages.pytest
    pythonPackages.ipython
    pythonPackages.black
    pythonPackages.pylint
    pythonPackages.bandit
  ];
in
{
  config.devcontainer.profiles."language/python" = {
    kind = "language";
    group = "31-python-language";
    packages = packages;
    priority = 72;
    stability = "medium";
    sharing = "image-family";
    securityClass = "trusted";
    provides.commands = [
      "uv"
      "uvx"
      "pipx"
      "ruff"
      "mypy"
      "pytest"
      "ipython"
      "black"
      "pylint"
      "bandit"
    ];
    vscode = {
      extensions = {
        "ms-python.python" = {
          native = true;
          bucket = "82-vscode-extensions-python";
          companionTools = [ "python" ];
        };
        "ms-python.vscode-pylance" = {
          native = true;
          bucket = "82-vscode-extensions-python";
          companionTools = [ "python" ];
        };
        "ms-python.autopep8" = {
          native = true;
          bucket = "82-vscode-extensions-python";
          companionTools = [ "python" ];
        };
        "charliermarsh.ruff" = {
          native = false;
          bucket = "82-vscode-extensions-python";
          companionTools = [ "ruff" ];
        };
      };
      settings = {
        "python.defaultInterpreterPath" = "/usr/bin/python";
        "[python]" = {
          "editor.defaultFormatter" = "charliermarsh.ruff";
        };
        "ruff.nativeServer" = "on";
      };
    };
    tests.capabilities = [ "language.python" ];
  };
}
