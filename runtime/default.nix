{ pkgs, lib }:
let
  writeShellApp =
    name: runtimeInputs: scriptPath:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile scriptPath;
    };
in
{
  "devcontainer-entrypoint" = writeShellApp "devcontainer-entrypoint" [
    pkgs.coreutils
  ] ./devcontainer-entrypoint/main.sh;
  "devcontainer-task-runner" = writeShellApp "devcontainer-task-runner" [
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.jq
    pkgs.moreutils
  ] ./devcontainer-task-runner/main.sh;
  "vscode-extension-projector" = writeShellApp "vscode-extension-projector" [
    pkgs.bash
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.jq
  ] ./vscode-extension-projector/main.sh;
  devpkg = writeShellApp "devpkg" [
    pkgs.bash
    pkgs.coreutils
    pkgs.gnused
    pkgs.jq
    pkgs.nix
  ] ./devpkg/main.sh;
  "devcontainer-image" = writeShellApp "devcontainer-image" [
    pkgs.bash
    pkgs.coreutils
    pkgs.diffutils
    pkgs.gnugrep
    pkgs.jq
  ] ./devcontainer-image/main.sh;
}
