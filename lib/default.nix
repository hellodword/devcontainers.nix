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

  features = {

    dev0 = pkgs: {
      name = "dev0";
      layered = false;

      packages = with pkgs; [
        git
        jq
        wget
        curl
      ];

      vscodeSettings = {
        "git.enabled" = true;
        "git.enableSmartCommit" = false;
        "git.enableCommitSigning" = false;
        "git.enableStatusBarSync" = false;
        "git.openRepositoryInParentFolders" = "always";
      };
    };

    dev1 = pkgs: {
      name = "dev1";
      layered = false;

      packages = with pkgs; [
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
      };
    };

    dev2 = pkgs: {
      name = "dev2";
      layered = false;

      packages = with pkgs; [
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
      extensions = with pkgs.vscode-extensions; [
        esbenp.prettier-vscode
      ];
      vscodeSettings = {
        "json.format.enable" = false;
        "[json]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[jsonc]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[markdown]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "prettier.enable" = true;
      };
    };

    # TODO nixpkgs
    # TODO cli
    # TODO features
    # https://github.com/NixOS/nix/blob/master/docker.nix
    nix = pkgs: {
      name = "nix";
      layered = true;

      packages = with pkgs; [
        nix

        nixd
        nixfmt-rfc-style
      ];
      extensions = with pkgs.vscode-extensions; [
        jnoortheen.nix-ide
      ];
      vscodeSettings = {
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
      };
    };

    # TODO cgo
    go = pkgs: {
      name = "go";
      layered = true;

      packages = with pkgs; [
        pkgs.go

        # https://github.com/golang/vscode-go/blob/eeb3c24fe991e47e130a0ac70a9b214664b4a0ea/extension/tools/allTools.ts.in
        delve
        gotools
        gopls
        go-outline
        gopkgs
        gomodifytags
        impl
        gotests
        go-tools
        golangci-lint

        k6
      ];
      extensions = with pkgs.vscode-extensions; [
        golang.go
      ];
      envVars = {
        GOTOOLCHAIN = "local";
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
    cpp = pkgs: {
      name = "cpp";
      layered = true;

      libraries = with pkgs; [ glib.dev ];

      packages = with pkgs; [
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

      extensions = with pkgs.vscode-extensions; [
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

    vala = pkgs: {
      name = "vala";
      layered = true;

      libraries = with pkgs; [ glib.dev ];

      packages = with pkgs; [
        vala
        vala-language-server

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
      pkgs:
      let
        dotnetCore = pkgs.dotnetCorePackages.sdk_8_0;
      in
      {
        name = "dotnet";
        layered = true;

        packages =
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

    node = pkgs: {
      name = "node";
      layered = true;

      packages = with pkgs; [
        nodejs
        typescript
        nodePackages.typescript-language-server
        yarn
        pnpm
      ];

      extensions = with pkgs.vscode-extensions; [
        dbaeumer.vscode-eslint
        vue.volar
      ];
      vscodeSettings = { };
    };

    rust = pkgs: { };

    java = pkgs: { };

    python = pkgs: { };

    php = pkgs: { };

    dart = pkgs: { };

    flutter = pkgs: { };

    android = pkgs: { };

    chromium = pkgs: { };

    aosp = pkgs: { };

    haskell = pkgs: { };

    lua = pkgs: { };

    zig = pkgs: { };

    swift = pkgs: { };

    gpu = pkgs: { };

    windows = pkgs: { };

    web3 = pkgs: { };

  };
}
