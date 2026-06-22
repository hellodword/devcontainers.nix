{
  pkgs,
  nixpkgs,
  images,
  ...
}:

{
  artifact-image-nix =
    pkgs.runCommand "artifact-image-nix"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${../../tests/ci/check-rootfs-layout.py} ${images.nix.rootfs} ${images.nix.reports} nix
        python3 ${../../tests/ci/check-image-tar.py} ${images.nix.oci} ${images.nix.reports} nix path:${nixpkgs.outPath}
        python3 ${../../tests/ci/check-image-tar-fixture.py} ${../..}
        touch "$out"
      '';

  artifact-rootfs-maximal =
    pkgs.runCommand "artifact-rootfs-maximal" { nativeBuildInputs = [ pkgs.python3 ]; }
      ''
        python3 ${../../tests/ci/check-rootfs-layout.py} ${images.flutter.rootfs} ${images.flutter.reports} flutter \
          --require /usr/bin/flutter \
          --require /usr/bin/rust-analyzer \
          --require /usr/bin/node \
          --require /usr/bin/python
        touch "$out"
      '';
}
