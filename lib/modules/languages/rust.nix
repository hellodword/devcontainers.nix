{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.devcontainer.languages.rust;
  defaultRustToolchain = pkgs.rust-bin.selectLatestNightlyWith (
    toolchain:
    toolchain.default.override {
      extensions = [
        "rust-src"
        "rustfmt"
        "clippy"
        "rust-analyzer"
      ];
    }
  );
  rustToolchain = if cfg.toolchain == null then defaultRustToolchain else cfg.toolchain;
  packages = [
    rustToolchain
    pkgs.cargo-nextest
    pkgs.cargo-edit
    pkgs.cargo-audit
    pkgs.rustup
  ];
in
{
  options.devcontainer.languages.rust.toolchain = mkOption {
    type = types.nullOr types.package;
    default = null;
  };

  config.devcontainer = {
    layers.bucketDefinitions = {
      "rust-language" = {
        order = 24000;
        owner = "languages/rust";
        purpose = "Rust toolchain, cargo helpers, and analyzer.";
      };
      "vscode-extensions-rust" = {
        order = 65000;
        owner = "languages/rust";
        purpose = "Rust Analyzer VS Code extension.";
      };
    };

    profiles."language/rust" = {
      kind = "language";
      group = "rust-language";
      packages = packages;
      priority = 70;
      stability = "medium";
      sharing = "image-family";
      securityClass = "trusted";
      provides.commands = [
        "rustc"
        "cargo"
        "rustfmt"
        "clippy-driver"
        "rust-analyzer"
        "cargo-nextest"
        "cargo-add"
        "cargo-rm"
        "cargo-upgrade"
        "cargo-audit"
        "rustup"
      ];
      libraries.presets = [ "rust-bindgen" ];
      vscode = {
        extensions."rust-lang.rust-analyzer" = {
          native = false;
          bucket = "vscode-extensions-rust";
          companionTools = [
            "rust-analyzer"
            "cargo"
            "clippy-driver"
          ];
        };
        settings = {
          "rust-analyzer.server.path" = "/usr/bin/rust-analyzer";
          "rust-analyzer.check.command" = "clippy";
        };
      };
      env = {
        variables = {
          RUST_BACKTRACE = "1";
          CARGO_HOME = "$XDG_DATA_HOME/cargo";
          RUSTUP_HOME = "$XDG_DATA_HOME/rustup";
          CARGO_TARGET_DIR = "$WORKSPACE/target";
        };
        path = [ "$CARGO_HOME/bin" ];
      };
      tests.cases."language.rust" = {
        tags = [
          "smoke"
          "language"
          "rust"
        ];
        command = [
          "bash"
          "-lc"
          "rustc --version && cargo --version && rustfmt --version && cargo clippy --version && rust-analyzer --version && rustup --version"
        ];
      };
    };
  };
}
