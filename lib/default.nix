# let
#   hello =
#     let
#       fromImageSha256 = {
#         "x86_64-linux" = "sha256-2Pf/eU9h9Ol6we9YjfYdTUQvjgd/7N7Tt5Mc1iOPkLU=";
#         "aarch64-linux" = "sha256-C75i+GJkPUN+Z+XSWHtunblM4l0kr7aT30Dqd0jjSTw=";
#       };
#     in
#     self.lib.mkDevcontainer ({
#       inherit pkgs;
#       name = "hello";
#       fromImage = pkgs.dockerTools.pullImage {
#         imageName = "mcr.microsoft.com/devcontainers/base";
#         imageDigest = "sha256:6155a486f236fd5127b76af33086029d64f64cf49dd504accb6e5f949098eb7e";
#         sha256 = fromImageSha256.${system};
#       };
#       paths = with pkgs; [
#         nixfmt-rfc-style
#         nixd
#         bash
#         coreutils
#         git
#         curl
#       ];
#       extensions = with pkgs.vscode-extensions; [
#         esbenp.prettier-vscode
#         jnoortheen.nix-ide
#       ];
#       envVars = {
#         FOO = "hello";
#       };
#     });
# in
{
  mkDevcontainer = import ./mkDevcontainer.nix;
  mkLayeredDevcontainer = import ./mkLayeredDevcontainer.nix;
  mkManuallyLayeredDevcontainer = import ./mkManuallyLayeredDevcontainer.nix;

  features =
    let
      ccPkgs = pkgs: with pkgs; [ stdenv.cc ];
      # mingwPkgs =
      #   pkgs: with pkgs.pkgsCross; [
      #     mingw32.buildPackages.gcc
      #     mingwW64.buildPackages.gcc
      #   ];

      prettierSettings = {
        "json.format.enable" = false;
        "prettier.enable" = true;
        "[json]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[jsonc]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[markdown]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
      };
    in
    {

      dev0 =
        { pkgs, ... }:
        {
          name = "dev0";
          layered = false;

          executables = with pkgs; [
            gitMinimal
            jq
            wget
            curl
            gawk
            diffutils
          ];

          vscodeSettings = {
            "git.enabled" = true;
            "git.enableSmartCommit" = false;
            "git.enableCommitSigning" = false;
            "git.enableStatusBarSync" = false;
            "git.openRepositoryInParentFolders" = "always";
          };

          alias = { };

          bashrc = ''
            # Set the default git editor if not already set
            if [ -z "$(git config --get core.editor)" ] && [ -z "${"$"}{GIT_EDITOR}" ]; then
                if  [ "${"$"}{TERM_PROGRAM}" = "vscode" ]; then
                    if [[ -n $(command -v code-insiders) &&  -z $(command -v code) ]]; then
                        export GIT_EDITOR="code-insiders --wait"
                    else
                        export GIT_EDITOR="code --wait"
                    fi
                fi
            fi
          '';
        };

      dev1 =
        { pkgs, ... }:
        {
          name = "dev1";
          layered = false;

          executables = with pkgs; [
            findutils
            iproute2
            iputils
            openssh
            which
            unzip
            zip
            vim
            file
            tree
            bzip2
            xz
            less
            lsof
            htop
          ];
          envVars = {
            PAGER = "less";
            EDITOR = "/bin/vim";
          };
          alias = {
            vi = "vim";
            ssh = "TERM=xterm-256color ssh";
          };
        };

      dev2 =
        { pkgs, ... }:
        {
          name = "dev2";
          layered = false;

          executables = with pkgs; [
            fd
            ripgrep
            (p7zip.override { enableUnfree = true; })

            aria2
            openssl
            netcat

            # /bin/uptime
            procps
            gnupg
            rsync
            # /bin/kill
            util-linux
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            esbenp.prettier-vscode
          ];
          vscodeSettings = prettierSettings;
        };

      # https://github.com/NixOS/nix/blob/master/docker.nix
      nix =
        { pkgs, envVarsDefault, ... }:
        let
          inherit (envVarsDefault) XDG_CONFIG_HOME;
          lib = pkgs.lib;
          nixConf = {
            sandbox = "false";
            build-users-group = "nixbld";
            substituters = [ "https://cache.nixos.org/" ];
            trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
            experimental-features = [
              "nix-command"
              "flakes"
            ];
          };
          nixConfContents =
            (lib.concatStringsSep "\n" (
              lib.attrsets.mapAttrsToList (
                n: v:
                let
                  vStr = if builtins.isList v then lib.concatStringsSep " " v else v;
                in
                "${n} = ${vStr}"
              ) nixConf
            ))
            + "\n"
            # GITHUB_TOKEN in codespaces
            # access-tokens = github.com=${GITHUB_TOKEN}
            + "!include ${XDG_CONFIG_HOME}/nix/access-token.conf"
            + "\n"
            + "!include ${XDG_CONFIG_HOME}/nix/nix.conf"
            + "\n";
          nixConfDir = pkgs.writeTextDir "nix.conf" nixConfContents;
        in
        {
          name = "nix";
          layered = true;

          executables = with pkgs; [
            nix

            nixd
            nixfmt-rfc-style
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            jnoortheen.nix-ide
          ];
          envVars = {
            NIX_PAGER = "cat";
            NIX_CONF_DIR = "${nixConfDir}";
            NIX_PATH = "nixpkgs=${pkgs.path}";
          };
          vscodeSettings = {
            "nix.enableLanguageServer" = true;
            "nix.serverPath" = "nixd";
          };

          onLogin =
            let
              nixAccessToken = pkgs.writeScript "exe" ''
                set -x
                if [ -n "$GITHUB_TOKEN" ]; then
                  mkdir -p "${XDG_CONFIG_HOME}/nix"
                  echo "access-tokens = github.com=$GITHUB_TOKEN" > "${XDG_CONFIG_HOME}/nix/access-token.conf"
                fi
              '';
            in
            {
              "write nix.conf#access-token" = {
                command = "${nixAccessToken}";
              };
            };
        };

      go =
        goPkg:
        { pkgs, envVarsDefault, ... }:
        let
          # https://github.com/cachix/devenv/blob/6bde92766ddd3ee1630029a03d36baddd51934e2/src/modules/languages/go.nix#L6
          # Override the buildGoModule function to use the specified Go package.
          buildGoModule = pkgs.buildGoModule.override { go = goPkg; };
          buildWithSpecificGo = pkg: pkg.override { inherit buildGoModule; };
        in
        {
          name = "go";
          layered = true;

          executables =
            [ goPkg ]
            ++ (with pkgs; [
              # https://github.com/golang/vscode-go/blob/eeb3c24fe991e47e130a0ac70a9b214664b4a0ea/extension/tools/allTools.ts.in
              # vscode-go expects all tool compiled with the same used go version
              # https://github.com/NixOS/nixpkgs/pull/383098
              (buildWithSpecificGo gopls)
              (buildWithSpecificGo gotests)
              (buildWithSpecificGo gomodifytags)
              (buildWithSpecificGo impl)

              # goplay

              (buildWithSpecificGo delve)
              # staticcheck
              (buildWithSpecificGo go-tools)

              # https://go.googlesource.com/tools
              (buildWithSpecificGo gotools)

              golangci-lint

              k6
            ])
            ++ (ccPkgs pkgs);
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            golang.go
          ];
          envVars = rec {
            inherit (envVarsDefault) HOME;
            GOTELEMETRY = "off";
            GOTOOLCHAIN = "local";
            GOROOT = "${pkgs.go}/share/go";
            GOPATH = "${HOME}/go";
            PATH = "${GOPATH}/bin";
            CGO_ENABLED = "1";
          };
          vscodeSettings = {
            "go.toolsManagement.checkForUpdates" = "off";
            "go.toolsManagement.autoUpdate" = false;
            "go.logging.level" = "verbose";
          };
          metadata = {
            # https://github.com/devcontainers/features/blob/c264b4e837f3273789fc83dae898152daae4cd90/src/go/devcontainer-feature.json#L38-L43
            "capAdd" = [
              "SYS_PTRACE"
            ];
            "securityOpt" = [
              "seccomp=unconfined"
            ];
          };
        };

      # https://github.com/devcontainers/images/tree/main/src/cpp
      # https://discourse.nixos.org/t/how-to-set-up-a-nix-shell-with-gnu-build-toolchain-build-essential/38579
      cpp =
        { pkgs, ... }:
        {
          name = "cpp";
          layered = true;

          libraries = with pkgs; [ glib.dev ];

          executables = with pkgs; [
            gnumake
            clang
            pkg-config
            cmake
            vcpkg
            lldb
            llvm
            gdb
            valgrind
            cppcheck

            bison
            flex
            fontforge
            makeWrapper
            gcc
            libiconv
            autoconf
            automake
            libtool # freetype calls glibtoolize

            clang-tools
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            ms-vscode.cpptools
            ms-vscode.cpptools-extension-pack
            ms-vscode.cmake-tools
          ];
          vscodeSettings = {
            # TODO
          };
          metadata = {
            "capAdd" = [
              "SYS_PTRACE"
            ];
            "securityOpt" = [
              "seccomp=unconfined"
            ];
          };
        };

      vala =
        { pkgs, ... }:
        {
          name = "vala";
          layered = true;

          libraries = with pkgs; [ glib.dev ];

          executables = with pkgs; [
            vala
            vala-language-server
            uncrustify

            clang
            pkg-config
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            prince781.vala
          ];
          vscodeSettings = {
            "vala.languageServerPath" = "/bin/vala-language-server";
          };
        };

      dotnet =
        dotnetCore:
        { pkgs, ... }:
        {
          name = "dotnet";
          layered = true;

          executables =
            [ dotnetCore ]
            ++ (with pkgs; [
              netcoredbg
            ]);

          extensions = with pkgs.vscode-extensions; [
            ms-dotnettools.vscodeintellicode-csharp
            ms-dotnettools.csdevkit
            ms-dotnettools.csharp
            ms-dotnettools.vscode-dotnet-runtime
          ];
          envVars = {
            DOTNET_NOLOGO = true;
            DOTNET_CLI_TELEMETRY_OPTOUT = true;
            DOTNET_SKIP_FIRST_TIME_EXPERIENCE = true;
            DOTNET_ROOT = "${dotnetCore}";
          };
          vscodeSettings = { };
        };

      node =
        nodePkg:
        { pkgs, ... }:
        {
          name = "node";
          layered = true;

          executables =
            [ nodePkg ]
            # ++ (with pkgs; [
            #   yarn
            #   pnpm
            # ])
            ++ (with nodePkg.pkgs; [
              typescript
              typescript-language-server
              yarn
              pnpm
            ]);

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            esbenp.prettier-vscode
            dbaeumer.vscode-eslint
            vue.volar
          ];
          envVars = {
            NODE_ENV = "development";
          };
          vscodeSettings = pkgs.lib.attrsets.recursiveUpdate prettierSettings {
            "[javascript]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
            "[typescript]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
          };
        };

      rust =
        { pkgs, envVarsDefault, ... }:
        {
          name = "rust";
          layered = true;

          executables = with pkgs; [
            stdenv.cc
            openssl
            openssl.dev
            pkg-config

            (rust-bin.stable.latest.default.override {
              extensions = [
                "rust-src"
                "rust-analyzer"
                "rustfmt"
                "clippy"
                "rust-std"
              ];
              # targets = [
              #   "x86_64-unknown-linux-gnu"
              # ];
            })
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            rust-lang.rust-analyzer
          ];
          envVars = rec {
            inherit (envVarsDefault) HOME;
            RUST_BACKTRACE = 1;
            CARGO_HOME = "${HOME}/.cargo";
            PATH = "${CARGO_HOME}/bin";
          };
          vscodeSettings = {
            # https://github.com/nix-community/nix-vscode-extensions/blob/adcb8b54d64484bb74f1480acefc3c686f318917/mkExtension.nix#L99-L109
            "rust-analyzer.server.path" = "/bin/rust-analyzer";
          };
        };

      java =
        jdkPkg:
        { pkgs, envVarsDefault, ... }:
        {
          name = "java";
          layered = true;

          executables =
            (with pkgs; [
              maven
              gradle
              kotlin
            ])
            ++ [ jdkPkg ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            vscjava.vscode-maven
            vscjava.vscode-gradle

            vscjava.vscode-java-pack
            # `vscjava.vscode-java-pack` won't work without others
            vscjava.vscode-java-dependency
            vscjava.vscode-java-debug
            visualstudioexptteam.intellicode-api-usage-examples
            vscjava.vscode-java-test
            visualstudioexptteam.vscodeintellicode
            redhat.java

            # TODO kotlin
          ];
          envVars = rec {
            inherit (envVarsDefault) XDG_DATA_HOME;
            JAVA_HOME = jdkPkg.home;
            SDKMAN_DIR = "${XDG_DATA_HOME}/sdkman";
            GRADLE_USER_HOME = "${XDG_DATA_HOME}/gradle";
            PATH = "${JAVA_HOME}/bin:${SDKMAN_DIR}/bin:${GRADLE_USER_HOME}/bin";
          };
          vscodeSettings = {
            "java.import.gradle.java.home" = jdkPkg.home;
            "java.autobuild.enabled" = false;
            "java.compile.nullAnalysis.mode" = "disabled";
          };
        };

      python =
        pyPkg:
        { pkgs, envVarsDefault, ... }:
        {
          name = "python";
          layered = true;

          executables =
            [ pyPkg ]
            # ++ (with pkgs; [
            #   pipenv
            #   virtualenv
            # ])
            ++ (with pyPkg.pkgs; [
              flake8
              autopep8
              black
              yapf
              mypy
              pydocstyle
              pycodestyle
              bandit
              pytest
              pylint

              pipx

              setuptools
              gitpython
            ]);

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            ms-python.python
            ms-python.vscode-pylance
            ms-python.autopep8
          ];
          envVars = rec {
            inherit (envVarsDefault)
              XDG_DATA_HOME
              XDG_CACHE_HOME
              XDG_CONFIG_HOME
              XDG_STATE_HOME
              ;

            PYTHON_PATH = "/bin/python";
            PYTHONUSERBASE = "${XDG_DATA_HOME}/python";

            PYTHONPYCACHEPREFIX = "${XDG_CACHE_HOME}/python";
            PYTHON_EGG_CACHE = "${XDG_CACHE_HOME}/python-eggs";

            MYPY_CACHE_DIR = "${XDG_CACHE_HOME}/mypy";

            JUPYTER_CONFIG_DIR = "${XDG_CONFIG_HOME}/jupyter";
            JUPYTER_PLATFORM_DIRS = "1";

            PYLINTRC = "${XDG_CONFIG_HOME}/pylint/pylintrc";

            PYTHON_HISTORY = "${XDG_STATE_HOME}/python/history";

            PIPX_HOME = "${XDG_DATA_HOME}/pipx";
            PIPX_BIN_DIR = "${PIPX_HOME}/bin";
            PIPX_GLOBAL_HOME = "${XDG_DATA_HOME}/pipx-global";
            PIPX_GLOBAL_BIN_DIR = "${PIPX_GLOBAL_HOME}/bin";
            PYENV = "${XDG_DATA_HOME}/pyenv";
          };
          vscodeSettings = {
            "python.defaultInterpreterPath" = "/bin/python";
            "[python]" = {
              "editor.defaultFormatter" = "ms-python.autopep8";
            };
          };
        };

      php =
        { pkgs, ... }:
        let
          phpPkg = pkgs.php;
          phpWithExt = phpPkg.buildEnv {
            extensions =
              { all, ... }:
              with all;
              [
                dom
                filter
                imagick
                mbstring
                opcache
                openssl
                session
                simplexml
                tokenizer
                xdebug
                xmlwriter
                zip
              ];
            # https://stackoverflow.com/a/69142727
            extraConfig = ''
              xdebug.mode = debug
              xdebug.start_with_request = trigger
              xdebug.client_port = 9003
            '';
          };
        in
        {
          name = "php";
          layered = true;

          executables =
            [ phpWithExt ]
            ++ (with phpPkg.packages; [
              composer
              phive
            ]);

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            xdebug.php-debug
            bmewburn.vscode-intelephense-client
            mrmlnc.vscode-apache
          ];
          envVars = { };
          vscodeSettings = {
            "php.validate.executablePath" = "/bin/php";
          };
        };

      # TODO minimize ghc and hls
      haskell =
        { pkgs, envVarsDefault, ... }:
        {
          name = "haskell";
          layered = true;

          libraries = with pkgs; [
            zlib
          ];

          executables = with pkgs; [
            ghc
            haskell-language-server
            stack
            cabal-install
            hpack
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            haskell.haskell
            justusadam.language-haskell
          ];
          envVars = rec {
            inherit (envVarsDefault) XDG_DATA_HOME XDG_CONFIG_HOME;
            GHCUP_USE_XDG_DIRS = "1";
            CABAL_DIR = "${XDG_DATA_HOME}/cabal";
            STACK_ROOT = "${XDG_DATA_HOME}/stack";
            STACK_XDG = "1";
          };
          vscodeSettings = {
            "haskell.manageHLS" = "PATH";
          };
        };

      dart =
        { pkgs, ... }:
        {
          name = "dart";
          layered = true;

          executables = with pkgs; [
            dart
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            dart-code.dart-code
          ];
          envVars = { };
          vscodeSettings = {
            "dart.checkForSdkUpdates" = false;
            "dart.updateDevTools" = false;
            "dart.debugSdkLibraries" = true;
          };
          onLogin = {
            "dart disable analytics" = {
              command = "dart --disable-analytics || true";
              once = true;
            };
          };
        };

      # TODO android
      flutter =
        { pkgs, ... }:
        let
          flutterPkg = pkgs.flutter;
        in
        {
          name = "flutter";
          layered = true;

          executables = [ flutterPkg ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            dart-code.dart-code
            dart-code.flutter
          ];
          envVars = {
            FLUTTER_ROOT = "${flutterPkg}";
            # FLUTTER_HOME
            # "PATH": "$PATH:$FLUTTER_HOME/bin"
          };
          vscodeSettings = {
            "dart.checkForSdkUpdates" = false;
            "dart.updateDevTools" = false;
            "dart.debugSdkLibraries" = true;
          };
          metadata = { };
          onLogin = {
            "dart disable analytics" = {
              command = "dart --disable-analytics || true";
              once = true;
            };
            "flutter disable analytics" = {
              command = "flutter --disable-analytics || true";
              once = true;
            };
          };
        };

      chromium = { ... }: { };

      aosp = { ... }: { };

      lua =
        { pkgs, ... }:
        {
          name = "lua";
          layered = true;

          executables = with pkgs; [
            lua
            lua-language-server
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            sumneko.lua
          ];
          envVars = { };
          vscodeSettings = { };
        };

      zig =
        { pkgs, ... }:
        {
          name = "zig";
          layered = true;

          executables = with pkgs; [
            zig
            zls
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            ziglang.vscode-zig
          ];
          envVars = { };
          vscodeSettings = {
            "zig.path" = "/bin/zig";
            "zig.zls.path" = "/bin/zls";
            "zig.checkForUpdate" = false;
            "zig.initialSetupDone" = true;
            "zig.formattingProvider" = "zls";
            "[zig]" = {
              "editor.defaultFormatter" = "ziglang.vscode-zig";
            };
          };
        };

      # FIXME
      swift =
        { pkgs, ... }:
        {
          name = "swift";
          layered = true;

          libraries = with pkgs; [
            gcc-unwrapped.lib
            libgcc
            swift
            glibc

            libedit
            ncurses5
            util-linux
            zlib
          ];

          executables = with pkgs; [
            sourcekit-lsp
            swift
            swift-format
            swiftPackages.swiftpm
            clang
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            swiftlang.swift-vscode
          ];
          envVars = { };
          vscodeSettings = {
            # "lldb.library" = "${pkgs.swift}/lib/liblldb.so";
            # "swift.backgroundCompilation" = true;
          };
        };

      gpu = { ... }: { };

      windows = { ... }: { };

      web3 = { ... }: { };

    };
}
