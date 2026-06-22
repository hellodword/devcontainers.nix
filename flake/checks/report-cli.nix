{ pkgs, compiler, images, ... }:

{
  report-cli-core =
    pkgs.runCommand "report-cli-core"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.jq
        ];
      }
      ''
        bash ${../../tests/ci/check-report-cli.sh} ${
          compiler.runtimePackages."devcontainer-image"
        } ${images.nix-latest.reports} nix-latest
        touch "$out"
      '';
}
