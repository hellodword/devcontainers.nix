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
      "31-python-language" = {
        order = 19;
        owner = "languages/python";
        purpose = "Python language tooling and linters.";
      };
      "82-vscode-extensions-python" = {
        order = 31;
        owner = "languages/python";
        purpose = "Python VS Code extension bundle.";
      };
    };

    profiles."language/python" = {
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
      tests.cases."language.python" = {
        tags = [
          "smoke"
          "language"
          "python"
        ];
        command = [
          "bash"
          "-lc"
          "pipx --version && ruff --version && mypy --version && pytest --version && ipython --version && black --version && pylint --version && bandit --version"
        ];
      };
    };
  };
}
