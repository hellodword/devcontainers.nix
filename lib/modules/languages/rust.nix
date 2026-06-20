{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.devcontainer.languages.rust;
  defaultRustToolchain = pkgs.rust-bin.nightly.latest.default.override {
    extensions = [
      "rust-src"
      "rustfmt"
      "clippy"
      "rust-analyzer"
    ];
  };
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
  config = lib.mkIf cfg.enable {
    environment.systemPackages = packages;
    devcontainer.libraries.presets = lib.mkBefore [ "rust-bindgen" ];
    devcontainer.vscode.extensions = [
      "rust-lang.rust-analyzer"
      "tamasfe.even-better-toml"
    ];
    devcontainer.vscode.settings = {
      "rust-analyzer.server.path" = "/usr/bin/rust-analyzer";
      "rust-analyzer.check.command" = "clippy";
    };
    environment.variables = {
      RUST_BACKTRACE = "1";
      CARGO_HOME = "$XDG_DATA_HOME/cargo";
      RUSTUP_HOME = "$XDG_DATA_HOME/rustup";
      CARGO_TARGET_DIR = "$WORKSPACE/target";
    };
    environment.variableOrigins = {
      RUST_BACKTRACE = [ "languages.rust" ];
      CARGO_HOME = [ "languages.rust" ];
      RUSTUP_HOME = [ "languages.rust" ];
      CARGO_TARGET_DIR = [ "languages.rust" ];
    };
    devcontainer.path.segments.language = [ "$CARGO_HOME/bin" ];
    devcontainer.path.segmentOrigins.language = {
      "$CARGO_HOME/bin" = [ "languages.rust" ];
    };
    devcontainer.graph.nodes."language/rust" = {
      kind = "language";
      group = "51-rust-language";
      paths = packages;
      stability = "medium";
      sharing = "image-family";
      priority = 70;
      securityClass = "trusted";
    };
    devcontainer.tests.smoke = [
      {
        name = "rustc-version";
        command = [
          "rustc"
          "--version"
        ];
      }
      {
        name = "cargo-version";
        command = [
          "cargo"
          "--version"
        ];
      }
      {
        name = "rust-tooling";
        command = [
          "bash"
          "-lc"
          "rustfmt --version && cargo clippy --version && rust-analyzer --version && rustup --version"
        ];
      }
      {
        name = "rust-runtime-deps";
        command = [
          "bash"
          "-lc"
          "python --version && node --version && cc --version"
        ];
      }
    ];
  };
}
