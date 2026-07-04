{
  pkgs,
  lib,
  nixpkgs,
  images,
  targets,
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
          export PYTHONPATH=${../../tests/ci}
          python3 ${../../tests/ci/check-image-tar.py} ${image.oci} ${image.reports} ${name} path:${nixpkgs.outPath}
          touch "$out"
        ''
    )
  ) images;
  rootfsChecks = lib.listToAttrs (
    map (
      target:
      let
        checkName = "artifact-rootfs-${target.target}";
        requireArgs = lib.concatMapStringsSep " " (path: "--require ${lib.escapeShellArg path}") (
          target.checks.rootfsRequires or [ ]
        );
      in
      lib.nameValuePair checkName (
        pkgs.runCommand checkName
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            export PYTHONPATH=${../../tests/ci}
            python3 ${../../tests/ci/check-rootfs-layout.py} ${images.${target.target}.rootfs} ${
              images.${target.target}.reports
            } ${target.target} ${requireArgs}
            touch "$out"
          ''
      )
    ) targets.imageTargetList
  );
  imageTarFixtureCheck = {
    artifact-image-fixture =
      pkgs.runCommand "artifact-image-fixture"
        {
          nativeBuildInputs = [ pkgs.python3 ];
        }
        ''
          python3 ${../../tests/ci/check-image-tar-fixture.py} ${../..}
          touch "$out"
        '';
  };
in
artifactImageChecks // rootfsChecks // imageTarFixtureCheck
