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
      ccPkgs =
        pkgs: with pkgs; [
          stdenv.cc
          stdenv.cc.bintools

          pkg-config
          autoconf
          automake
          gnumake
        ];
      ccLibs =
        pkgs: with pkgs; [
          zlib.out
          zlib.dev

          openssl.out
          openssl.dev

          libxml2.out
          libxml2.dev

          curl.out
          curl.dev

          zstd.out
          zstd.dev

          xz.out
          xz.dev

          gtest.out
          gtest.dev
        ];
      metadataPtrace = {
        # https://github.com/devcontainers/features/blob/c264b4e837f3273789fc83dae898152daae4cd90/src/go/devcontainer-feature.json#L38-L43
        "capAdd" = [
          "SYS_PTRACE"
        ];
        "securityOpt" = [
          "seccomp=unconfined"
        ];
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

            stdenv.cc.bintools
          ];
          envVars = {
            PAGER = "less";
            EDITOR = pkgs.lib.getExe pkgs.vim;
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

            procps
            gnupg
            rsync
            util-linux
          ];
        };

      prettier =
        { pkgs, ... }:
        {
          name = "prettier";
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            esbenp.prettier-vscode
          ];
          vscodeSettings = {
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
            "[javascript]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
            "[typescript]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
            "[yaml]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
          };
        };

      # https://github.com/NixOS/nix/blob/master/docker.nix
      nix-core =
        { pkgs, envVarsDefault, ... }:
        let
          inherit (envVarsDefault) XDG_CONFIG_HOME HOME XDG_STATE_HOME;
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
            accept-flake-config = "true";
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
          name = "nix-core";
          layered = true;

          executables = with pkgs; [
            nix

            # required by nix* --help
            man

            nix-index-with-db
          ];
          envVars = {
            NIX_PAGER = "cat";
            NIX_CONF_DIR = "${nixConfDir}";
            NIX_PATH = "nixpkgs=${pkgs.path}";
            PATH = "${HOME}/.nix-profile/bin:${XDG_STATE_HOME}/nix/profiles/profile/bin";
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
          alias = {
            "nix-env-add" = ''nix-env --verbose -f "<nixpkgs>" -iA'';
          };
        };

      nix =
        { pkgs, ... }:
        {
          name = "nix";
          layered = true;

          executables = with pkgs; [
            nixd
            nixfmt-rfc-style
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            jnoortheen.nix-ide
          ];
          vscodeSettings = {
            "nix.enableLanguageServer" = true;
            "nix.serverPath" = "nixd";
            "files.associations" = {
              "**/flake.lock" = "json";
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
            ]);
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
          metadata = metadataPtrace;
        };

      # https://github.com/devcontainers/images/tree/main/src/cpp
      # https://discourse.nixos.org/t/how-to-set-up-a-nix-shell-with-gnu-build-toolchain-build-essential/38579
      cc =
        { pkgs, ... }:
        {
          name = "cc";
          layered = true;
          libraries = ccLibs pkgs;
          executables = ccPkgs pkgs;
        };

      # TODO remove gcc and keep mingw gcc
      mingw64 =
        { pkgs, ... }:
        let
          useWin32ThreadModel =
            stdenv:
            pkgs.overrideCC stdenv (
              stdenv.cc.override (old: {
                cc = old.cc.override {
                  threadsCross = {
                    model = "win32";
                    package = null;
                  };
                };
              })
            );
          mingwW64Stdenv = useWin32ThreadModel pkgs.pkgsCross.mingwW64.stdenv;
        in
        {
          name = "mingw64";
          layered = true;
          executables = [ mingwW64Stdenv.cc ];
        };

      cpp =
        { pkgs, ... }:
        {
          name = "cpp";
          layered = true;

          # libraries = with pkgs; [
          #   # glib.dev
          #   # stdenv.cc.cc.lib
          #   # libiconv
          #   # libtool
          # ];

          libraries = ccLibs pkgs;
          executables = ccPkgs pkgs;
          # for ms-vscode.cpptools
          deps = with pkgs; [ clang-tools ];
          # ++ (with pkgs; [

          #   # clang
          #   # vcpkg
          #   # lldb
          #   # llvm
          #   # valgrind
          #   # cppcheck

          #   # # clangd
          #   # clang-tools
          # ]);

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # FIXME too large because of the clang-tools: pkgs/applications/editors/vscode/extensions/ms-vscode.cpptools/default.nix
            # build a static clangd and set the `"C_Cpp.clang_format_path"`?
            ms-vscode.cpptools
            ms-vscode.cpptools-extension-pack
          ];
        };

      gdb =
        { pkgs, ... }:
        {
          name = "gdb";
          layered = true;
          executables = with pkgs; [
            gdb
          ];
          metadata = metadataPtrace;
        };

      cmake =
        { pkgs, ... }:
        {
          name = "cmake";
          layered = true;
          executables = with pkgs; [
            cmake
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            ms-vscode.cmake-tools
          ];
          envVarsFunc = {
            CMAKE_PREFIX_PATH =
              feat:
              (
                if
                  builtins.hasAttr "envVars" feat
                  && builtins.hasAttr "CMAKE_PREFIX_PATH" feat.envVars
                  && builtins.stringLength feat.envVars.CMAKE_PREFIX_PATH > 0
                then
                  feat.envVars.CMAKE_PREFIX_PATH + ":"
                else
                  ""
              )
              + (pkgs.lib.makeSearchPath "lib/cmake" (feat.libraries or [ ]));
          };

          vscodeSettings = {
            "cmake.enableAutomaticKitScan" = false;
            "cmake.cmakePath" = pkgs.lib.getExe' pkgs.cmake "cmake";
            "cmake.cpackPath" = pkgs.lib.getExe' pkgs.cmake "cpack";
            "cmake.ctestPath" = pkgs.lib.getExe' pkgs.cmake "ctest";
          };
        };

      meson =
        { pkgs, ... }:
        {
          name = "meson";
          layered = true;
          executables = with pkgs; [
            meson
            mesonlsp
            muon
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/mesonbuild/vscode-meson
            mesonbuild.mesonbuild
          ];
          vscodeSettings = {
            "mesonbuild.downloadLanguageServer" = false;
            "mesonbuild.languageServer" = "mesonlsp";
            "mesonbuild.languageServerPath" = pkgs.lib.getExe pkgs.mesonlsp;
            "mesonbuild.mesonPath" = pkgs.lib.getExe pkgs.meson;
            "mesonbuild.muonPath" = pkgs.lib.getExe pkgs.muon;
            "mesonbuild.mesonlsp.others.muonPath" = pkgs.lib.getExe pkgs.muon;
            "mesonbuild.formatting.enabled" = true;
            "[meson]" = {
              "editor.defaultFormatter" = "mesonbuild.mesonbuild";
            };
            "mesonbuild.formatting.provider" = "auto";
            "mesonbuild.linting.enabled" = true;
            # any security issue?
            "mesonbuild.configureOnOpen" = true;
          };
        };

      ninja =
        { pkgs, ... }:
        {
          name = "ninja";
          layered = true;
          executables = with pkgs; [
            ninja
          ];
        };

      gn =
        { pkgs, ... }:
        {
          name = "gn";
          layered = true;
          executables = with pkgs; [
            gn
          ];
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

            # clang
            # pkg-config
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            prince781.vala
          ];
          vscodeSettings = {
            "vala.languageServerPath" = pkgs.lib.getExe pkgs.vala-language-server;
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
            dbaeumer.vscode-eslint
            vue.volar
          ];
          envVars = {
            NODE_ENV = "development";
          };
        };

      rust =
        { pkgs, envVarsDefault, ... }:
        let
          rustBin = pkgs.rust-bin.stable.latest.default.override {
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
          };
        in
        {
          name = "rust";
          layered = true;

          libraries = with pkgs; [
            openssl.dev
          ];

          deps = with rustBin.availableComponents; [
            rust-docs
            rust-analyzer-preview
            clippy-preview
            rustfmt-preview
            rust-std
            cargo
            rust-src
          ];

          executables =
            [ rustBin ]
            ++ (with pkgs; [
              openssl

              # stdenv.cc
              # pkg-config
            ]);

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
            "rust-analyzer.server.path" = pkgs.lib.getExe pkgs.rust-analyzer;
          };
        };

      java =
        jdkPkg:
        { pkgs, envVarsDefault, ... }:
        let
          # https://github.com/ratson/nixtras/blob/af65f24d77f2829761263bc501ce017014bc412e/pkgs/kotlin-debug-adapter.nix
          kotlin-debug-adapter = pkgs.stdenv.mkDerivation rec {
            pname = "kotlin-debug-adapter";
            version = "0.4.4";

            src = pkgs.fetchzip {
              url = "https://github.com/fwcd/kotlin-debug-adapter/releases/download/${version}/adapter.zip";
              hash = "sha256-gNbGomFcWqOLTa83/RWS4xpRGr+jmkovns9Sy7HX9bg=";
            };

            installPhase = ''
              runHook preInstall

              mkdir -p $out/{bin,libexec}
              cp -a . "$out/libexec/${pname}"
              ln -s "$out/libexec/${pname}/bin/${pname}" "$out/bin/${pname}"

              runHook postInstall
            '';
          };
        in
        {
          name = "java";
          layered = true;

          executables =
            (with pkgs; [
              maven
              gradle
              kotlin
              kotlin-language-server
              kotlin-debug-adapter
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

            # https://github.com/fwcd/vscode-kotlin
            fwcd.kotlin
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
            "kotlin.languageServer.enabled" = true;
            "kotlin.languageServer.path" =
              pkgs.lib.getExe' pkgs.kotlin-language-server "kotlin-language-server";
            "kotlin.debugAdapter.enabled" = true;
            "kotlin.debugAdapter.path" = pkgs.lib.getExe' kotlin-debug-adapter "kotlin-debug-adapter";
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
            ++ (with pkgs; [
              pipenv
              virtualenv
              poetry
              uv
            ])
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

            PYTHON_PATH = pkgs.lib.getExe pyPkg;
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
            "python.defaultInterpreterPath" = pkgs.lib.getExe pyPkg;
            "[python]" = {
              "editor.defaultFormatter" = "ms-python.autopep8";
            };
          };
        };

      php =
        { pkgs, envVarsDefault, ... }:
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
            ])
            ++ [ pkgs.laravel ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            xdebug.php-debug
            bmewburn.vscode-intelephense-client
            mrmlnc.vscode-apache
            # https://github.com/laravel/vs-code-extension
            laravel.vscode-laravel
          ];
          envVars = rec {
            inherit (envVarsDefault) XDG_CONFIG_HOME;
            # for `composer global require foo-cli`
            PATH = "${XDG_CONFIG_HOME}/composer/vendor/bin";
          };
          vscodeSettings = {
            "php.validate.executablePath" = pkgs.lib.getExe phpWithExt;
            "php.debug.executablePath" = pkgs.lib.getExe phpWithExt;
            "php.suggest.basic" = true;
            "php.validate.enable" = true;
            "php.validate.run" = "onSave";

          };
        };

      # TODO minimize ghc and hls
      haskell =
        { pkgs, envVarsDefault, ... }:
        {
          name = "haskell";
          layered = true;

          executables =
            (with pkgs; [
              ghc
              haskell-language-server
              # stack
              cabal-install
              hpack
            ])
            ++ (with pkgs.haskellPackages; [
              cabal-gild
              ormolu
              fourmolu
              cabal-fmt
              ghci-dap
              haskell-debug-adapter
            ]);

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            haskell.haskell
            justusadam.language-haskell
            phoityne.phoityne-vscode
          ];
          envVars = rec {
            inherit (envVarsDefault) XDG_DATA_HOME XDG_CONFIG_HOME;
            GHCUP_USE_XDG_DIRS = "1";
            CABAL_DIR = "${XDG_DATA_HOME}/cabal";
            PATH = "${CABAL_DIR}/bin";
            # STACK_ROOT = "${XDG_DATA_HOME}/stack";
            # STACK_XDG = "1";
          };
          vscodeSettings = {
            "haskell.manageHLS" = "PATH";
            "haskell.formattingProvider" = "ormolu";
            # "haskell.serverExecutablePath" = "";
            "haskell.plugin.fourmolu.config.path" = pkgs.lib.getExe pkgs.haskellPackages.fourmolu;
            "haskell.plugin.cabal-fmt.config.path" = pkgs.lib.getExe pkgs.haskellPackages.cabal-fmt;
            "haskell.plugin.cabal-gild.config.path" = pkgs.lib.getExe pkgs.haskellPackages.cabal-gild;
          };
        };

      dart =
        { pkgs, envVarsDefault, ... }:
        {
          name = "dart";
          layered = true;

          executables = with pkgs; [ dart ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            dart-code.dart-code
          ];
          envVars = rec {
            inherit (envVarsDefault) HOME;
            PATH = "${HOME}/.pub-cache/bin";
          };
          vscodeSettings = {
            "dart.checkForSdkUpdates" = false;
            "dart.updateDevTools" = false;
            "dart.debugSdkLibraries" = true;
            "dart.debugExtensionBackendProtocol" = "ws";
            "dart.debugExternalPackageLibraries" = true;
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

      # TODO: https://github.com/nvim-neorocks/lux
      # TODO: formatter https://github.com/JohnnyMorganz/StyLua
      # TODO: linter https://github.com/lunarmodules/luacheck
      lua =
        { pkgs, envVarsDefault, ... }:
        let
          luaPkg = pkgs.lua5_4_compat;
          shortVersion = builtins.concatStringsSep "." (
            pkgs.lib.lists.take 2 (builtins.splitVersion luaPkg.version)
          );
        in
        {
          name = "lua";
          layered = true;

          executables =
            [ luaPkg ]
            ++ (with pkgs; [
              lua-language-server
            ])
            ++ (with luaPkg.pkgs; [
              luarocks
            ]);

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            sumneko.lua
          ];
          envVars = rec {
            inherit (envVarsDefault) HOME;
            PATH = "${HOME}/.luarocks/bin";
            LUA_PATH = "${HOME}/.luarocks/share/lua/${shortVersion}/?.lua;;";
            LUA_CPATH = "${HOME}/.luarocks/lib/lua/${shortVersion}/?.so;;";
          };
          onLogin = {
            "luarocks local_by_default" = {
              command = "luarocks config local_by_default true";
              once = true;
            };
          };
        };

      zigcc =
        { pkgs, ... }:
        {
          name = "zigcc";
          executables = with pkgs; [
            zig
          ];
          envVars = {
            /*
              $ zig --help | grep drop-in
                ar               Use Zig as a drop-in archiver
                cc               Use Zig as a drop-in C compiler
                c++              Use Zig as a drop-in C++ compiler
                dlltool          Use Zig as a drop-in dlltool.exe
                lib              Use Zig as a drop-in lib.exe
                ranlib           Use Zig as a drop-in ranlib
                objcopy          Use Zig as a drop-in objcopy
                rc               Use Zig as a drop-in rc.exe
            */

            ZIG_AR_WINDOWS = "zig ar -target x86_64-windows-gnu";
            ZIG_CC_WINDOWS = "zig cc -target x86_64-windows-gnu";
            ZIG_CXX_WINDOWS = "zig c++ -target x86_64-windows-gnu";
            ZIG_LD_WINDOWS = "zig ld -target x86_64-windows-gnu";

            ZIG_AR_LINUX = "zig ar -target x86_64-linux-gnu";
            ZIG_CC_LINUX = "zig cc -target x86_64-linux-gnu";
            ZIG_CXX_LINUX = "zig c++ -target x86_64-linux-gnu";
            ZIG_LD_LINUX = "zig ld -target x86_64-linux-gnu";
          };
        };

      clibs-windows =
        { pkgs, ... }:
        let
          winLibraries = ccLibs pkgs.pkgsCross.mingwW64;
        in
        {
          name = "clibs-windows";
          layered = true;
          deps = winLibraries;
          envVars = {
            WINDOWS_LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath winLibraries;
            WINDOWS_PKG_CONFIG_PATH = pkgs.lib.makeSearchPath "lib/pkgconfig" winLibraries;
            WINDOWS_CMAKE_PREFIX_PATH = pkgs.lib.makeSearchPath "lib/cmake" winLibraries;
          };
        };

      wine =
        { pkgs, ... }:
        {
          name = "wine";
          layered = true;
          executables = with pkgs; [
            wineWowPackages.stable
          ];
          envVars = {
            # https://github.com/Woynert/notas-tambien/blob/2fc1dced7280e045010cfc1db2444b98cddd8590/shell.nix#L146-L147
            WINEDLLOVERRIDES = "mscoree,mshtml=";
          };
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
          vscodeSettings = {
            "zig.path" = pkgs.lib.getExe pkgs.zig;
            "zig.zls.path" = pkgs.lib.getExe pkgs.zls;
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
          vscodeSettings = {
            # "lldb.library" = "${pkgs.swift}/lib/liblldb.so";
            # "swift.backgroundCompilation" = true;
          };
        };

      # https://github.com/koalaman/shellcheck
      # https://github.com/vscode-shellcheck/vscode-shellcheck
      shellcheck =
        { pkgs, ... }:
        {
          name = "shellcheck";
          layered = true;

          executables = with pkgs; [ shellcheck ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            timonwong.shellcheck
          ];
          vscodeSettings = {
            "shellcheck.enable" = true;
            "shellcheck.enableQuickFix" = true;
            "shellcheck.run" = "onSave";
            # do not use the precompiled binaries
            "shellcheck.executablePath" = pkgs.lib.getExe pkgs.shellcheck;
            "shellcheck.exclude" = [ ];
            "shellcheck.customArgs" = [ ];
            "shellcheck.ignorePatterns" = {
              "**/*.csh" = true;
              "**/*.cshrc" = true;
              "**/*.fish" = true;
              "**/*.login" = true;
              "**/*.logout" = true;
              "**/*.tcsh" = true;
              "**/*.tcshrc" = true;
              "**/*.xonshrc" = true;
              "**/*.xsh" = true;
              "**/*.zsh" = true;
              "**/*.zshrc" = true;
              "**/zshrc" = true;
              "**/*.zprofile" = true;
              "**/zprofile" = true;
              "**/*.zlogin" = true;
              "**/zlogin" = true;
              "**/*.zlogout" = true;
              "**/zlogout" = true;
              "**/*.zshenv" = true;
              "**/zshenv" = true;
              "**/*.zsh-theme" = true;
            };
            "shellcheck.ignoreFileSchemes" = [
              "git"
              "gitfs"
              "output"
            ];
          };
        };

      grammarly =
        { pkgs, ... }:
        {
          name = "grammarly";
          executables = with pkgs; [
            harper
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/automattic/harper
            elijah-potter.harper
          ];
          vscodeSettings = {
            "harper.markdown.IgnoreLinkTitle" = true;
            # do not use the precompiled binaries
            "harper.path" = pkgs.lib.getExe pkgs.harper;

            "harper.linters.SentenceCapitalization" = false;
            "harper.linters.RepeatedWords" = false;
            "harper.linters.LongSentences" = false;
            "harper.linters.Dashes" = false;
            "harper.linters.ToDoHyphen" = false;
            "harper.linters.ExpandMinimum" = false;
            "harper.linters.Spaces" = false;

            "harper.userDictPath" = ../.harper.dict;
          };
        };

      markdown =
        { pkgs, ... }:
        {
          name = "markdown";
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/shd101wyy/vscode-markdown-preview-enhanced
            shd101wyy.markdown-preview-enhanced
          ];
          vscodeSettings = {
            "markdown-preview-enhanced.liveUpdate" = false;
          };
        };

      autocorrect =
        { pkgs, ... }:
        {
          name = "autocorrect";
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/huacnlee/vscode-autocorrect
            huacnlee.autocorrect
          ];
          vscodeSettings = {
            "autocorrect.enable" = true;
            "autocorrect.enableLint" = true;
            # override this
            "autocorrect.formatOnSave" = false;
          };
        };

      # TODO minimize texlive
      latex =
        { pkgs, ... }:
        {
          name = "latex";
          layered = true;

          executables = with pkgs; [
            texliveMedium
            # tectonic
            # ltex-ls
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/James-Yu/LaTeX-Workshop
            james-yu.latex-workshop
          ];
          vscodeSettings = {
            "latex-workshop.formatting.latex" = "latexindent";
            "latex-workshop.latex.tools" = [
              {
                "name" = "latexmk";
                "command" = "latexmk";
                "args" = [
                  "-synctex=1"
                  "-interaction=nonstopmode"
                  "-file-line-error"
                  "-pdf"
                  "-outdir=%OUTDIR%"
                  "%DOC%"
                ];
              }
              {
                "name" = "bibtex";
                "command" = "bibtex";
                "env" = { };
                "args" = [ "%DOCFILE%" ];
              }
            ];
            "latex-workshop.latex.recipes" = [
              {
                "name" = "latexmk 🔃";
                "tools" = [ "latexmk" ];
              }
            ];
            "latex-workshop.view.pdf.viewer" = "tab";
          };
        };

      xml =
        { pkgs, ... }:
        {
          name = "xml";
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            redhat.vscode-xml
          ];
          vscodeSettings = {
            "xml.format.enabled" = true;
          };
        };

      toml =
        { pkgs, ... }:
        {
          name = "toml";
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            tamasfe.even-better-toml
          ];
          vscodeSettings = {
            "[toml]" = {
              "editor.defaultFormatter" = "tamasfe.even-better-toml";
            };
            "evenBetterToml.formatter.crlf" = false;
          };
        };

      nginx =
        { pkgs, ... }:
        {
          name = "nginx";
          executables = with pkgs; [
            nginx
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/raynigon/vscode-nginx-formatter
            raynigon.nginx-formatter
            # https://github.com/ahmadalli/vscode-nginx-conf
            ahmadalli.vscode-nginx-conf
          ];
          vscodeSettings = {
            # https://github.com/ahmadalli/vscode-nginx-conf#formatting
            "[nginx]" = {
              "editor.defaultFormatter" = "raynigon.nginx-formatter";
            };
          };
        };

      pg =
        { pkgs, ... }:
        {
          name = "pg";
          executables = with pkgs; [
            postgres-lsp
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/supabase-community/postgres-language-server/tree/main/editors/code
            Supabase.postgrestools
          ];
          vscodeSettings = {
            "postgrestools.bin" = pkgs.lib.getExe pkgs.postgres-lsp;
          };
        };

      drawio =
        { pkgs, ... }:
        {
          name = "drawio";
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/hediet/vscode-drawio
            hediet.vscode-drawio
          ];
        };

      # TODO formatter linter
      # https://graphviz.org/doc/info/lang.html
      graphviz =
        { pkgs, ... }:
        {
          name = "graphviz";
          executables = with pkgs; [
            graphviz
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/EFanZh/Graphviz-Preview
            efanzh.graphviz-preview
          ];
          vscodeSettings = {
            "graphvizPreview.dotPath" = pkgs.lib.getExe' pkgs.graphviz "dot";
          };
        };

      jinja =
        { pkgs, ... }:
        {
          name = "jinja";
          layered = true;
          executables = with pkgs; [
            minijinja
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            samuelcolvin.jinjahtml
          ];
        };

      chromium = { ... }: { };

      aosp = { ... }: { };

      gpu = { ... }: { };

      llvm = { ... }: { };

      tailscale = { ... }: { };

      # binfmt
      qemu = { ... }: { };

      /*
        ranking:
          https://aider.chat/docs/leaderboards/
          https://openrouter.ai/rankings/programming

        buy:
          https://www.requesty.ai/
          https://openrouter.ai
          https://cloud.google.com/vertex-ai/pricing
      */
      copilot =
        { pkgs, ... }:
        {
          name = "copilot";
          layered = true;
          executables = with pkgs; [
            # https://docs.continue.dev/customize/deep-dives/codebase#ignore-files-during-indexing
            sqlite
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # # https://github.com/RooVetGit/Roo-Code
            # rooveterinaryinc.roo-cline

            # https://github.com/continuedev/continue
            continue.continue
          ];
          vscodeSettings = {
            "files.associations" = {
              "**/.continueignore" = "plaintext";
            };

            "continue.telemetryEnabled" = false;
            "continue.enableConsole" = true;
            "continue.pauseCodebaseIndexOnStart" = true;
          };
          onLogin = {
            "init continue" = {
              command = ''
                mkdir -p ~/.continue/index
                touch ~/.continue/.env
                cat ${../.continue/assistants/config.yaml} > ~/.continue/config.yaml
                cat ${../.continueignore} > ~/.continue/.continueignore

                # workaround of declarative `disableAutocompleteInFiles`
                # https://docs.continue.dev/json-reference#fully-deprecated-settings
                echo '${
                  builtins.toJSON {
                    sharedConfig.disableAutocompleteInFiles = pkgs.lib.lists.unique (
                      [
                        "*.md"
                      ]
                      ++ (pkgs.lib.filter (
                        x: builtins.typeOf x == "string" && pkgs.lib.strings.match "^[^# \t][^\r\n]*" x != null
                      ) (builtins.split "\n" (builtins.readFile ../.continueignore)))
                    );
                  }
                }' > ~/.continue/index/globalContext.json
              '';
              once = true;
            };
          };
        };
    };
}
