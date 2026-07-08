{
  pkgs,
  ...
}:
let
  packages = with pkgs; [
    clang
    clang-tools
    cmake-language-server
    gdb
    lldb
    bear
    cppcheck
  ];
in
{
  config.devcontainer = {
    layers.bucketDefinitions = {
      "cpp-language" = {
        order = 23200;
        owner = "languages/cpp";
        purpose = "C and C++ compiler, language server, debugger, and static analysis tooling.";
      };
      "vscode-extensions-cpp" = {
        order = 64200;
        owner = "languages/cpp";
        purpose = "C and C++ VS Code extensions.";
      };
    };

    profiles."language/cpp" = {
      kind = "language";
      group = "cpp-language";
      packages = [ ];
      priority = 68;
      stability = "medium";
      sharing = "image-family";
      securityClass = "trusted";
      composition.role = "bundle";
      includes = [
        "runtime/c-env"
        "language/cpp/core"
        "language/cpp/smoke"
      ];
    };

    profiles."language/cpp/core" = {
      kind = "language";
      group = "cpp-language";
      packages = packages;
      priority = 68;
      stability = "medium";
      sharing = "image-family";
      securityClass = "trusted";
      provides.commands = [
        "clang"
        "clang++"
        "clangd"
        "clang-format"
        "clang-tidy"
        "cmake-language-server"
        "gdb"
        "lldb"
        "lldb-dap"
        "bear"
        "cppcheck"
      ];
      vscode = {
        extensions = {
          "llvm-vs-code-extensions.vscode-clangd" = {
            native = false;
            bucket = "vscode-extensions-cpp";
            companionTools = [
              "clangd"
              "clang-format"
              "clang-tidy"
            ];
          };
          "ms-vscode.cmake-tools" = {
            native = false;
            bucket = "vscode-extensions-cpp";
            companionTools = [
              "cmake"
              "cmake-language-server"
            ];
          };
          "vadimcn.vscode-lldb" = {
            native = true;
            bucket = "vscode-extensions-cpp";
            sourcePreference = "open-vsx-first";
            companionTools = [
              "lldb"
              "lldb-dap"
            ];
          };
        };
        settings = {
          "clangd.path" = "/usr/bin/clangd";
          "clangd.arguments" = [
            "--background-index"
            "--clang-tidy"
          ];
          "cmake.configureOnOpen" = false;
          "cmake.cmakePath" = "/usr/bin/cmake";
        };
      };
    };

    profiles."language/cpp/smoke" = {
      kind = "language";
      group = "cpp-language";
      packages = [ ];
      priority = 68;
      stability = "medium";
      sharing = "image-family";
      securityClass = "trusted";
      tests.cases."language.cpp" = {
        tags = [
          "smoke"
          "language"
          "cpp"
          "c"
        ];
        scripts = [
          {
            shell = "bash";
            interactive = false;
            command = ''
              set -e
              clang --version
              clang++ --version
              clangd --version
              clang-format --version
              clang-tidy --version
              command -v cmake-language-server >/dev/null
              gdb --version
              lldb --version
              command -v lldb-dap bear cppcheck >/dev/null
            '';
          }
        ];
      };
    };
  };
}
