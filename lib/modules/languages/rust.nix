{
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
  config.devcontainer.profiles."language/rust" = {
    kind = "language";
    group = "51-rust-language";
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
        bucket = "85-vscode-extensions-rust";
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
}
