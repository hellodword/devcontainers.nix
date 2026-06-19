{
  lib,
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
  config = lib.mkIf cfg.enable {
    devcontainer.runtimes.python.enable = true;
    devcontainer.packages = packages;
    devcontainer.vscode.extensions = [
      "ms-python.python"
      "charliermarsh.ruff"
    ];
    devcontainer.vscode.settings = {
      "python.defaultInterpreterPath" = "/usr/local/bin/python";
      "[python]" = {
        "editor.defaultFormatter" = "charliermarsh.ruff";
      };
      "ruff.nativeServer" = "on";
    };
    devcontainer.graph.nodes."language/python" = {
      kind = "language";
      group = "31-python-language";
      paths = packages;
      stability = "medium";
      sharing = "image-family";
      priority = 72;
      securityClass = "trusted";
    };
    devcontainer.tests.smoke = [
      {
        name = "python-version";
        command = [
          "python"
          "--version"
        ];
      }
      {
        name = "uv-version";
        command = [
          "uv"
          "--version"
        ];
      }
      {
        name = "uvx-version";
        command = [
          "uvx"
          "--version"
        ];
      }
      {
        name = "python-runtime-imports";
        command = [
          "bash"
          "-lc"
          "python -c 'import ssl, sqlite3, ctypes'"
        ];
      }
      {
        name = "python-node-runtime";
        command = [
          "bash"
          "-lc"
          "node --version && npm --version && npx --version"
        ];
      }
      {
        name = "nixd-version";
        command = [
          "nixd"
          "--version"
        ];
      }
    ];
  };
}
