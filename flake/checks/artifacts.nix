{
  pkgs,
  nixpkgs,
  images,
  ...
}:

{
  artifact-image-nix-latest =
    pkgs.runCommand "artifact-image-nix-latest"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${../../tests/ci/check-rootfs-layout.py} ${images.nix-latest.rootfs} ${images.nix-latest.reports} nix-latest
        python3 ${../../tests/ci/check-image-tar.py} ${images.nix-latest.oci} ${images.nix-latest.reports} nix-latest path:${nixpkgs.outPath}
        python3 ${../../tests/ci/check-image-tar-fixture.py} ${../..}
        touch "$out"
      '';

  artifact-rootfs-maximal =
    pkgs.runCommand "artifact-rootfs-maximal" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${../../tests/ci/check-rootfs-layout.py} ${images.flutter-latest.rootfs} ${images.flutter-latest.reports} flutter-latest \
          --require /usr/bin/flutter \
          --require /usr/bin/rust-analyzer \
          --require /usr/bin/node \
          --require /usr/bin/python
        touch "$out"
      '';
}
