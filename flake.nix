{
  description = "Modular Nix/OCI development container image";

  inputs = {
    core.url = "git+https://github.com/hellodword/nixos-config.git?ref=master&dir=infra";
    nixpkgs.follows = "core/nixpkgs";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix.follows = "core/treefmt-nix";
    llm-agents.url = "github:numtide/llm-agents.nix";
    nix2container = {
      url = "github:nlewo/nix2container";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      core,
      nixpkgs,
      rust-overlay,
      nix-vscode-extensions,
      nix-index-database,
      treefmt-nix,
      nix2container,
      ...
    }:
    let
      system = "x86_64-linux";
      nixpkgsConfig = {
        allowUnfree = true;
        android_sdk.accept_license = true;
        oraclejdk.accept_license = true;
        allowUnsupportedSystem = true;
      };
      pkgs = import nixpkgs {
        inherit system;
        config = nixpkgsConfig;
        overlays = [
          nix-vscode-extensions.overlays.default
          (final: prev: {
            inherit (nix2container.packages.${system})
              nix2container
              nix2container-bin
              skopeo-nix2container
              ;
          })
          rust-overlay.overlays.default
          nix-index-database.overlays.nix-index
        ];
      };
      inherit (pkgs) lib;
      cacheLayout = builtins.fromJSON (builtins.readFile ./data/cache-layout.json);
      cacheLayoutFile = pkgs.runCommandLocal "devcontainer-cache-layout.json" { } ''
        install -m 0644 ${./data/cache-layout.json} "$out"
      '';
      cache = import ./nix/cache.nix { inherit core lib; };
      images = import ./nix/images.nix {
        inherit
          self
          pkgs
          lib
          inputs
          system
          cache
          cacheLayout
          ;
      };
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      mkClosedShellApp =
        {
          name,
          runtimeInputs,
          text,
        }:
        let
          closedPath = lib.makeBinPath runtimeInputs;
        in
        pkgs.runCommand name
          {
            nativeBuildInputs = [ pkgs.shellcheck ];
          }
          ''
            mkdir -p "$out/bin"
            cat > "$out/bin/${name}" <<'WRAPPER_EOF'
            #!${pkgs.bash}/bin/bash
            set -euo pipefail
            export PATH=${lib.escapeShellArg closedPath}
            export PYTHONNOUSERSITE=1
            ${text}
            WRAPPER_EOF
            chmod 0755 "$out/bin/${name}"
            ${pkgs.bash}/bin/bash -n "$out/bin/${name}"
            shellcheck --shell=bash "$out/bin/${name}"
          '';

      loadAppPkg = mkClosedShellApp {
        name = "load-devcontainer-image";
        runtimeInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.docker-client
          pkgs.jq
          pkgs.skopeo-nix2container
        ];
        text = ''
          export OCI_DIR=${lib.escapeShellArg "${images.oci}"}
          exec ${pkgs.bash}/bin/bash ${./scripts/load-image.sh} "$@"
        '';
      };

      publishAppPkg = mkClosedShellApp {
        name = "publish-devcontainers";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.skopeo-nix2container
        ];
        text = ''
          exec ${pkgs.python3}/bin/python3 -I ${./scripts/publish.py} "$@"
        '';
      };

      cacheScopesFile = pkgs.writeText "devcontainers-cache-config.nix" ''
        {
          local.text = ${builtins.toJSON cache.local.text};
          public.text = ${builtins.toJSON cache.public.text};
          ci.text = ${builtins.toJSON cache.ci.text};
        }
      '';

      nixCacheAppPkg = mkClosedShellApp {
        name = "devcontainers-nix-cache";
        runtimeInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.nix
        ];
        text = ''
          exec ${pkgs.bash}/bin/bash ${core}/scripts/nix-cache.sh \
            --config-file ${cacheScopesFile} \
            --fragment-name "devcontainers-nix-cache.conf" \
            "$@"
        '';
      };

      verifyAppPkg = mkClosedShellApp {
        name = "verify-devcontainers";
        runtimeInputs = [
          pkgs.skopeo-nix2container
          core.packages.${system}.ci-tools
          core.packages.${system}.oranc
          pkgs.bash
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.git
          pkgs.jq
          pkgs.nix
          pkgs.python3
          pkgs.zstd
        ];
        text = ''
          exec ${pkgs.python3}/bin/python3 -I ${./tests/verify.py} "$@"
        '';
      };
    in
    {
      formatter.${system} = treefmtEval.config.build.wrapper;

      packages.${system} = {
        inherit (images) image oci;
        cache-layout = cacheLayoutFile;
        default = images.oci;
      };

      apps.${system} = rec {
        load = {
          type = "app";
          program = "${loadAppPkg}/bin/load-devcontainer-image";
          meta.description = "Load ghcr.io/hellodword/devcontainers-dev:latest into the local Docker daemon";
        };
        publish = {
          type = "app";
          program = "${publishAppPkg}/bin/publish-devcontainers";
          meta.description = "Publish digest-preserving OCI tags to a registry";
        };
        nix-cache = {
          type = "app";
          program = "${nixCacheAppPkg}/bin/devcontainers-nix-cache";
          meta.description = "Print or install signed OCI and public Nix binary cache settings";
        };
        verify = {
          type = "app";
          program = "${verifyAppPkg}/bin/verify-devcontainers";
          meta.description = "Run static checks, OCI layout validation, release tests, and VM acceptance suites";
        };
        default = load;
      };

      checks.${system} = {
        formatting = treefmtEval.config.build.check self;
        lint = import ./nix/lint.nix {
          inherit
            self
            pkgs
            lib
            images
            cacheLayout
            ;
        };
        runtime-cache =
          let
            tiniClosure = pkgs.closureInfo { rootPaths = [ pkgs.tini ]; };
            runtimeCacheTestSrc = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./data/cache-layout.json
                ./runtime/devcontainer-runtime/cache_gc.py
                ./runtime/devcontainer-runtime/state.py
                ./tests/check_runtime_cache.py
              ];
            };
          in
          pkgs.runCommand "devcontainers-runtime-cache"
            {
              nativeBuildInputs = [ pkgs.python3 ];
            }
            ''
              export HOME="$TMPDIR/home"
              export XDG_CACHE_HOME="$TMPDIR/cache"
              export NIX_STATE_DIR="$TMPDIR/nix/var/nix"
              export NIX_LOG_DIR="$TMPDIR/nix/var/log/nix"
              export NIX_CONF_DIR="$TMPDIR/nix/etc"
              unset NIX_REMOTE
              mkdir -p "$HOME" "$XDG_CACHE_HOME" "$NIX_STATE_DIR" "$NIX_LOG_DIR" "$NIX_CONF_DIR"
              printf 'sandbox = false\nexperimental-features = nix-command flakes\n' > "$NIX_CONF_DIR/nix.conf"
              ${pkgs.nix}/bin/nix-store --load-db < ${tiniClosure}/registration
              ${pkgs.python3}/bin/python3 -sE ${runtimeCacheTestSrc}/tests/check_runtime_cache.py \
                --post-build-hook ${images.runtime.devcontainer-nix-post-build}/bin/devcontainer-nix-post-build \
                --nix-bin ${pkgs.nix}/bin/nix \
                --sample-store-path ${pkgs.tini}
              touch "$out"
            '';
        publish =
          let
            publishTestSrc = lib.fileset.toSource {
              root = ./.;
              fileset = lib.fileset.unions [
                ./flake.lock
                ./scripts/publish.py
                ./tests/check_publish.py
              ];
            };
          in
          pkgs.runCommand "devcontainers-publish"
            {
              nativeBuildInputs = [
                pkgs.distribution
                pkgs.git
                pkgs.python3
                pkgs.skopeo-nix2container
              ];
            }
            ''
              export HOME="$TMPDIR/home"
              export XDG_CONFIG_HOME="$TMPDIR/config"
              export XDG_CACHE_HOME="$TMPDIR/cache"
              export XDG_RUNTIME_DIR="$TMPDIR/run"
              mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
              ${pkgs.python3}/bin/python3 -sE ${publishTestSrc}/tests/check_publish.py \
                --publish-bin ${publishAppPkg}/bin/publish-devcontainers \
                --oci-dir ${images.oci}
              touch "$out"
            '';
        vm-containers = import ./tests/vm/containers.nix {
          inherit
            pkgs
            core
            inputs
            images
            ;
        };
        vm-editor = import ./tests/vm/editor.nix {
          inherit
            pkgs
            core
            images
            ;
        };
      };

      devShells.${system}.default = pkgs.mkShellNoCC {
        shellHook = ''
          export PYTHONNOUSERSITE=1
        '';
        packages = [
          pkgs.skopeo-nix2container
          core.packages.${system}.ci-tools
          core.packages.${system}.oranc
          pkgs.actionlint
          pkgs.distribution
          pkgs.gh
          pkgs.git
          pkgs.jq
          pkgs.nix.out
          pkgs.nixfmt
          pkgs.prettier
          pkgs.python3
          pkgs.ruff
          pkgs.shellcheck
          pkgs.shfmt
          pkgs.tini
          pkgs.zstd
        ];
      };

      lib = {
        inherit cacheLayout;
        ${system} = {
          inherit
            cache
            cacheLayout
            images
            pkgs
            publishAppPkg
            ;
        };
      };
    };
}
