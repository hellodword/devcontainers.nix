# Rust Nightly toolchain (with rust-src, rustfmt, clippy, rust-analyzer), cargo plugins, and rustup.
{ pkgs }:
let
  rustToolchain = pkgs.rust-bin.selectLatestNightlyWith (
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
  # Expose only the `rustup` binary in /usr/bin so `rustc`/`cargo` resolve directly
  # to the preinstalled Nightly toolchain while `$CARGO_HOME/bin` precedes `/usr/bin` in PATH.
  rustupCli = pkgs.runCommand "rustup-cli" { } ''
    mkdir -p "$out/bin"
    ln -s ${pkgs.rustup}/bin/rustup "$out/bin/rustup"
  '';
  usrPackages = [
    rustToolchain
    pkgs.cargo-nextest
    pkgs.cargo-edit
    pkgs.cargo-audit
    rustupCli
  ];
  cacheEnv = {
    CARGO_HOME = "/home/vscode/.local/share/cargo";
    RUSTUP_HOME = "/home/vscode/.local/share/rustup";
  };
  devEnv = {
    RUST_BACKTRACE = "1";
  };
in
{
  inherit
    usrPackages
    rustToolchain
    cacheEnv
    devEnv
    ;
  storeDeps = [
    rustToolchain
    pkgs.cargo-nextest
    pkgs.cargo-edit
    pkgs.cargo-audit
    pkgs.rustup
    rustupCli
  ];
  pathSegments = [ "/home/vscode/.local/share/cargo/bin" ];
  env = cacheEnv // devEnv;
}
