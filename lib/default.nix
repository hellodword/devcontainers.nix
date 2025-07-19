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
      ccCore =
        pkgs: with pkgs; [
          stdenv.cc
          stdenv.cc.bintools
        ];
      ccBin =
        pkgs: with pkgs; [
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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "dev0";
          inherit layered;

          executables = with pkgs; [
            gitMinimal
            jq
            wget
            curl
            gawk
            diffutils
            perl
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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "dev1";
          inherit layered;

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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "dev2";
          inherit layered;

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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "prettier";
          inherit layered;
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
        {
          layered ? true,
        }:
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
          inherit layered;

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
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "nix";
          inherit layered;

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
        {
          goPackage,
          layered ? true,
        }:
        { pkgs, envVarsDefault, ... }:
        let
          # https://github.com/cachix/devenv/blob/6bde92766ddd3ee1630029a03d36baddd51934e2/src/modules/languages/go.nix#L6
          # Override the buildGoModule function to use the specified Go package.
          buildGoModule = pkgs.buildGoModule.override { go = goPackage; };
          buildWithSpecificGo = pkg: pkg.override { inherit buildGoModule; };
          # buildWithSpecificLatestGo = pkg: pkg.override { buildGoLatestModule = buildGoModule; };
        in
        {
          name = "go";
          inherit layered;

          executables =
            [ goPackage ]
            ++ (with pkgs; [
              gopls
              # https://github.com/golang/vscode-go/blob/eeb3c24fe991e47e130a0ac70a9b214664b4a0ea/extension/tools/allTools.ts.in
              # vscode-go expects all tool compiled with the same used go version
              # https://github.com/NixOS/nixpkgs/pull/383098
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
              protoc-gen-go
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
            CGO_ENABLED = "0";
          };
          vscodeSettings = {
            "go.toolsManagement.checkForUpdates" = "off";
            "go.toolsManagement.autoUpdate" = false;
            "go.logging.level" = "verbose";
          };
          alias = {
            go-build = ''go build -trimpath -ldflags "-s -w -buildid="'';
          };
          metadata = metadataPtrace;
        };

      # https://github.com/devcontainers/images/tree/main/src/cpp
      # https://discourse.nixos.org/t/how-to-set-up-a-nix-shell-with-gnu-build-toolchain-build-essential/38579
      cc =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "cc";
          inherit layered;
          libraries = ccLibs pkgs;
          executables = (ccCore pkgs) ++ (ccBin pkgs);
        };

      # TODO remove gcc and keep mingw gcc
      mingw64 =
        {
          layered ? false,
        }:
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
          inherit layered;
          executables = [ mingwW64Stdenv.cc ];
        };
      mingw32 =
        {
          layered ? false,
        }:
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
          mingw32Stdenv = useWin32ThreadModel pkgs.pkgsCross.mingw32.stdenv;
        in
        {
          name = "mingw32";
          inherit layered;
          executables = [ mingw32Stdenv.cc ];
        };

      cpp =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "cpp";
          inherit layered;

          # libraries = with pkgs; [
          #   # glib.dev
          #   # stdenv.cc.cc.lib
          #   # libiconv
          #   # libtool
          # ];

          libraries = ccLibs pkgs;
          executables = (ccCore pkgs) ++ (ccBin pkgs);
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
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "gdb";
          inherit layered;
          executables = with pkgs; [
            gdb
          ];
          metadata = metadataPtrace;
        };

      cmake =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "cmake";
          inherit layered;
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
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "meson";
          inherit layered;
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
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "ninja";
          inherit layered;
          executables = with pkgs; [
            ninja
          ];
        };

      gn =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "gn";
          inherit layered;
          executables = with pkgs; [
            gn
          ];
        };

      vala =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "vala";
          inherit layered;

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
        {
          dotnetPackage,
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "dotnet";
          inherit layered;

          executables =
            [ dotnetPackage ]
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
            DOTNET_ROOT = "${dotnetPackage}";
          };
        };

      node =
        {
          nodePackage,
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "node";
          inherit layered;

          executables =
            [ nodePackage ]
            # ++ (with pkgs; [
            #   yarn
            #   pnpm
            # ])
            ++ (with nodePackage.pkgs; [
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
        {
          layered ? true,
        }:
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
          inherit layered;

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
        {
          jdkPackage,
          layered ? true,
        }:
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
          inherit layered;

          executables =
            (with pkgs; [
              maven
              gradle
              kotlin
              kotlin-language-server
              kotlin-debug-adapter
            ])
            ++ [ jdkPackage ];

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
            JAVA_HOME = jdkPackage.home;
            SDKMAN_DIR = "${XDG_DATA_HOME}/sdkman";
            GRADLE_USER_HOME = "${XDG_DATA_HOME}/gradle";
            PATH = "${JAVA_HOME}/bin:${SDKMAN_DIR}/bin:${GRADLE_USER_HOME}/bin";
          };
          vscodeSettings = {
            "java.configuration.updateBuildConfiguration" = "automatic";
            "java.import.gradle.java.home" = jdkPackage.home;
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
        {
          pythonPackage,
          layered ? true,
        }:
        { pkgs, envVarsDefault, ... }:
        {
          name = "python";
          inherit layered;

          executables =
            [ pythonPackage ]
            ++ (with pkgs; [
              pipenv
              virtualenv
              poetry
              uv
            ])
            ++ (with pythonPackage.pkgs; [
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

            PYTHON_PATH = pkgs.lib.getExe pythonPackage;
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

            PATH = "${PIPX_BIN_DIR}:${PIPX_GLOBAL_BIN_DIR}";
          };
          vscodeSettings = {
            "python.defaultInterpreterPath" = pkgs.lib.getExe pythonPackage;
            "[python]" = {
              "editor.defaultFormatter" = "ms-python.autopep8";
            };
          };
        };

      php =
        {
          layered ? true,
        }:
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
          inherit layered;

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
        {
          layered ? true,
        }:
        { pkgs, envVarsDefault, ... }:
        {
          name = "haskell";
          inherit layered;

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
        {
          layered ? true,
        }:
        { pkgs, envVarsDefault, ... }:
        {
          name = "dart";
          inherit layered;

          executables = with pkgs; [
            dart
            protoc-gen-dart
          ];

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
        {
          layered ? true,
        }:
        { pkgs, ... }:
        let
          flutterPkg = pkgs.flutter;
        in
        {
          name = "flutter";
          inherit layered;

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
      lua =
        {
          layered ? true,
        }:
        { pkgs, envVarsDefault, ... }:
        let
          luaPkg = pkgs.lua5_4_compat;
          shortVersion = builtins.concatStringsSep "." (
            pkgs.lib.lists.take 2 (builtins.splitVersion luaPkg.version)
          );
        in
        {
          name = "lua";
          inherit layered;

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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "zigcc";
          inherit layered;

          executables =
            (with pkgs; [
              zig
            ])
            ++ (ccBin pkgs);
          envVars = rec {
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

            CC = ZIG_CC_LINUX;
            CXX = ZIG_CXX_LINUX;
          };
        };

      clibs-win64 =
        {
          layered ? false,
        }:
        { pkgs, ... }:
        let
          winLibraries = ccLibs pkgs.pkgsCross.mingwW64;
        in
        {
          name = "clibs-windows";
          inherit layered;
          deps = winLibraries;
          envVars = {
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath winLibraries;
            PKG_CONFIG_PATH = pkgs.lib.makeSearchPath "lib/pkgconfig" winLibraries;
            CMAKE_PREFIX_PATH = pkgs.lib.makeSearchPath "lib/cmake" winLibraries;
          };
        };

      wine =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "wine";
          inherit layered;
          executables = with pkgs; [
            wineWowPackages.stable
          ];
          envVars = {
            # https://github.com/Woynert/notas-tambien/blob/2fc1dced7280e045010cfc1db2444b98cddd8590/shell.nix#L146-L147
            WINEDLLOVERRIDES = "mscoree,mshtml=";
          };
        };

      zig =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "zig";
          inherit layered;

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
      # https://github.com/NixOS/nixpkgs/issues/242779
      swift =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "swift";
          inherit layered;

          libraries = with pkgs; [
            swiftPackages.swift
            swiftPackages.Dispatch
            swiftPackages.Foundation
            swiftPackages.XCTest

            swiftPackages.stdenv.cc.libc
            swiftPackages.stdenv.cc.libc_dev
            swiftPackages.stdenv.cc.libc_lib
          ];

          executables = with pkgs; [
            lldb

            swiftPackages.stdenv.cc

            swiftPackages.bintools
            swiftPackages.swift
            swiftPackages.swiftpm
            swiftPackages.swift-format
            swiftPackages.sourcekit-lsp
            swiftPackages.Dispatch
            swiftPackages.Foundation
            swiftPackages.XCTest
          ];

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            swiftlang.swift-vscode
            llvm-vs-code-extensions.lldb-dap
          ];
          vscodeSettings = {
            # "lldb.library" = "${pkgs.swift}/lib/liblldb.so";
            # "swift.backgroundCompilation" = true;
          };
        };

      # https://github.com/koalaman/shellcheck
      # https://github.com/vscode-shellcheck/vscode-shellcheck
      shellcheck =
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "shellcheck";
          inherit layered;

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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "grammarly";
          inherit layered;

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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "markdown";
          inherit layered;

          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/shd101wyy/vscode-markdown-preview-enhanced
            shd101wyy.markdown-preview-enhanced
          ];
          vscodeSettings = {
            "markdown-preview-enhanced.liveUpdate" = false;
          };
        };

      autocorrect =
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "autocorrect";
          inherit layered;
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
        {
          layered ? true,
        }:
        { pkgs, ... }:
        {
          name = "latex";
          inherit layered;

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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "xml";
          inherit layered;
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            redhat.vscode-xml
          ];
          vscodeSettings = {
            "xml.format.enabled" = true;
          };
        };

      toml =
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "toml";
          inherit layered;
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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "nginx";
          inherit layered;
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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "pg";
          inherit layered;
          executables = with pkgs; [
            postgres-lsp
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/supabase-community/postgres-language-server/tree/main/editors/code
            Supabase.postgrestools
            # https://techcommunity.microsoft.com/blog/adforpostgresql/announcing-a-new-ide-for-postgresql-in-vs-code-from-microsoft/4414648

            ms-ossdata.vscode-pgsql
          ];
          vscodeSettings = {
            "postgrestools.bin" = pkgs.lib.getExe pkgs.postgres-lsp;
          };
        };

      drawio =
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "drawio";
          inherit layered;
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/hediet/vscode-drawio
            hediet.vscode-drawio
          ];
        };

      # TODO formatter linter
      # https://graphviz.org/doc/info/lang.html
      graphviz =
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "graphviz";
          inherit layered;
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
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "jinja";
          inherit layered;
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

      msvc = { ... }: { };

      prolog = { ... }: { };

      /*
        ranking:
          https://aider.chat/docs/leaderboards/
          https://openrouter.ai/rankings/programming

        buy:
          https://www.requesty.ai/
          https://openrouter.ai
          https://cloud.google.com/vertex-ai/pricing
          https://aws.amazon.com/bedrock/
      */
      copilot =
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "copilot";
          inherit layered;
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

            # disable bundled GitHub Copilot
            "chat.agent.enabled" = false;
            "chat.mcp.enabled" = false;
            "chat.edits2.enabled" = false;
            "chat.commandCenter.enabled" = false;
            "chat.mcp.discovery.enabled" = false;
            "chat.extensionTools.enabled" = false;
            "chat.implicitContext.enabled" = {
              "panel" = "never";
              "editing-session" = "never";
            };
            "chat.detectParticipant.enabled" = false;
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

      protobuf =
        {
          layered ? false,
        }:
        { pkgs, ... }:
        {
          name = "protobuf";
          inherit layered;
          executables = with pkgs; [
            protobuf
            # https://github.com/coder3101/protols
            protols
          ];
          extensions = with (pkgs.forVSCodeVersion pkgs.vscode.version).vscode-marketplace; [
            # https://github.com/ianandhum/vscode-protobuf-support
            ianandhum.protobuf-support
          ];
          vscodeSettings = {
            "protobuf-support.protols.path" = pkgs.lib.getExe' pkgs.protols "protols";
          };
        };

    };
}
