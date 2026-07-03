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
  rootfsRequireTargets = builtins.filter (
    target: (target.checks.rootfsRequires or [ ]) != [ ]
  ) targets.imageTargetList;
  rootfsRequireChecks = lib.listToAttrs (
    map (
      target:
      let
        checkName =
          if builtins.length rootfsRequireTargets == 1 then
            "artifact-rootfs-maximal"
          else
            "artifact-rootfs-${target.target}";
        requireArgs = lib.concatMapStringsSep " " (
          path: "--require ${lib.escapeShellArg path}"
        ) target.checks.rootfsRequires;
      in
      lib.nameValuePair checkName (
        pkgs.runCommand checkName
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            python3 ${../../tests/ci/check-rootfs-layout.py} ${images.${target.target}.rootfs} ${
              images.${target.target}.reports
            } ${target.target} ${requireArgs}
            touch "$out"
          ''
      )
    ) rootfsRequireTargets
  );
in
artifactImageChecks // rootfsRequireChecks
