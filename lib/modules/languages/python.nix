{
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.languages.python;
  pythonPackages = if cfg.packageSet == null then pkgs.python3Packages else cfg.packageSet;
  packages = [
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
          native = false;
          bucket = "82-vscode-extensions-python";
          companionTools = [ "python" ];
        };
        "ms-python.vscode-pylance" = {
          native = false;
          bucket = "82-vscode-extensions-python";
          companionTools = [ "python" ];
        };
        "ms-python.debugpy" = {
          native = false;
          bucket = "82-vscode-extensions-python";
          companionTools = [ "python" ];
        };
        "ms-python.vscode-python-envs" = {
          native = false;
          bucket = "82-vscode-extensions-python";
          companionTools = [
            "python"
            "uv"
          ];
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
        "ruff.path" = [ "/usr/bin/ruff" ];
        "python-envs.alwaysUseUv" = true;
      };
    };
    tests.capabilities = [ "language.python" ];
  };
}
