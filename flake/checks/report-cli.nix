{
  pkgs,
  compiler,
  images,
  ...
}:

{
  report-cli-core =
    pkgs.runCommand "report-cli-core"
      {
        nativeBuildInputs = [
          pkgs.python3
        ];
      }
      ''
        python3 ${../../tests/ci/check-report-cli.py} ${
          compiler.runtimePackages."devcontainer-image"
        } ${images.nix.reports} nix
        touch "$out"
      '';
}
