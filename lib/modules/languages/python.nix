{
  lib,
  pkgs,
  config,
  ...
}:
let
  packages = with pkgs; [
    uv
    pipx
    python313Packages.ruff
    python313Packages.mypy
    python313Packages.pytest
    python313Packages.ipython
    python313Packages.black
    python313Packages.pylint
    python313Packages.bandit
  ];
in
{
  config = lib.mkIf config.devcontainer.languages.python.enable {
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
