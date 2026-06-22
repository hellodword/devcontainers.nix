{
  pkgs,
  lib,
  nixpkgs,
  images,
  ...
}:

let
  artifactImageChecks = lib.mapAttrs' (
    name: image:
    lib.nameValuePair "artifact-image-${name}" (
      pkgs.runCommand "artifact-image-${name}"
        {
          nativeBuildInputs = [ pkgs.python3 ];
        }
        ''
          ${lib.optionalString (name == "nix") ''
            python3 ${../../tests/ci/check-rootfs-layout.py} ${image.rootfs} ${image.reports} ${name}
          ''}
          python3 ${../../tests/ci/check-image-tar.py} ${image.oci} ${image.reports} ${name} path:${nixpkgs.outPath}
          ${lib.optionalString (name == "nix") ''
            python3 ${../../tests/ci/check-image-tar-fixture.py} ${../..}
          ''}
          touch "$out"
        ''
    )
  ) images;
in
artifactImageChecks
// {
  artifact-rootfs-maximal =
    pkgs.runCommand "artifact-rootfs-maximal"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${../../tests/ci/check-rootfs-layout.py} ${images.flutter.rootfs} ${images.flutter.reports} flutter \
          --require /usr/bin/flutter \
          --require /usr/bin/rust-analyzer \
          --require /usr/bin/node \
          --require /usr/bin/python
        touch "$out"
      '';
}
