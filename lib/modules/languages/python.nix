{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
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
  options.devcontainer.languages.python.packageSet = mkOption {
    type = types.nullOr types.attrs;
    default = null;
  };

  config.devcontainer = {
    layers.bucketDefinitions = {
      "python-language" = {
        order = 21100;
        owner = "languages/python";
        purpose = "Python language tooling and linters.";
      };
      "vscode-extensions-python" = {
        order = 62000;
        owner = "languages/python";
        purpose = "Python VS Code extension bundle.";
      };
    };

    profiles."language/python" = {
      kind = "language";
      group = "python-language";
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
            bucket = "vscode-extensions-python";
            companionTools = [ "python" ];
          };
          "ms-python.vscode-pylance" = {
            native = false;
            bucket = "vscode-extensions-python";
            companionTools = [ "python" ];
          };
          "ms-python.debugpy" = {
            native = false;
            bucket = "vscode-extensions-python";
            companionTools = [ "python" ];
          };
          "ms-python.vscode-python-envs" = {
            native = false;
            bucket = "vscode-extensions-python";
            companionTools = [
              "python"
              "uv"
            ];
          };
          "charliermarsh.ruff" = {
            native = false;
            bucket = "vscode-extensions-python";
            companionTools = [ "ruff" ];
          };
          "ms-python.mypy-type-checker" = {
            native = false;
            bucket = "vscode-extensions-python";
            companionTools = [ "mypy" ];
          };
          "ms-python.pylint" = {
            native = false;
            bucket = "vscode-extensions-python";
            companionTools = [ "pylint" ];
          };
          "ms-python.black-formatter" = {
            native = false;
            bucket = "vscode-extensions-python";
            companionTools = [ "black" ];
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
          "mypy-type-checker.importStrategy" = "fromEnvironment";
          "mypy-type-checker.path" = [ "/usr/bin/mypy" ];
          "pylint.importStrategy" = "fromEnvironment";
          "pylint.path" = [ "/usr/bin/pylint" ];
          "black-formatter.importStrategy" = "fromEnvironment";
          "black-formatter.path" = [ "/usr/bin/black" ];
        };
      };
      tests.cases."language.python" = {
        tags = [
          "smoke"
          "language"
          "python"
        ];
        scripts = [
          {
            shell = "bash";
            interactive = false;
            command = ''
              set -e
              pipx --version
              ruff --version
              mypy --version
              pytest --version
              ipython --version
              black --version
              pylint --version
              bandit --version
            '';
          }
        ];
      };
    };
  };
}
