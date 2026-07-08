{
  lib,
  images,
  contractLib,
  ...
}:

let
  requiredSymlinkTargets = [
    "/lib64/ld-linux-x86-64.so.2"
    "/usr/lib/libc.so.6"
    "/usr/lib/libstdc++.so.6"
  ];
  perImage = lib.mapAttrsToList (
    name: image:
    let
      fhs = image.fhsRuntime;
      symlinksByTarget = lib.listToAttrs (
        map (link: lib.nameValuePair link.target link) (fhs.symlinks or [ ])
      );
      sourceRoleFor = target: (symlinksByTarget.${target} or { }).sourceRole or null;
      missingSymlinks = builtins.filter (
        target: !(builtins.hasAttr target symlinksByTarget)
      ) requiredSymlinkTargets;
      caCertificates = fhs.caCertificates or { };
      realGlibcLoader = fhs.realGlibcLoader or null;
      nixLdLibraryPathInputs = fhs.nixLdLibraryPathInputs or [ ];
      hasLibraryInputRole = role: lib.any (entry: (entry.role or null) == role) nixLdLibraryPathInputs;
      checks = {
        enabled = fhs.enabled or false;
        dynamicLoaderMode = (fhs.dynamicLoaderMode or null) == "nix-ld";
        realGlibcLoader =
          contractLib.nonEmptyString realGlibcLoader && realGlibcLoader != "/lib64/ld-linux-x86-64.so.2";
        requiredSymlinksPresent = missingSymlinks == [ ];
        caBundle = (caCertificates.bundle or null) == "/etc/ssl/certs/ca-certificates.crt";
        caRoot = lib.hasInfix "ca-certificates" (caCertificates.root or "");
        caSource = lib.hasSuffix "/etc/ssl/certs/ca-certificates.crt" (caCertificates.source or "");
        libcSource = sourceRoleFor "/usr/lib/libc.so.6" == "glibc";
        libstdcxxSource = sourceRoleFor "/usr/lib/libstdc++.so.6" == "gcc-lib";
        dynamicLoaderSource = sourceRoleFor "/lib64/ld-linux-x86-64.so.2" == "nix-ld";
        nixLdEnvLoader = ((fhs.nixLdEnv or { }).NIX_LD or null) == realGlibcLoader;
        nixLdLibraryPathHasRuntimeLibs = hasLibraryInputRole "glibc" && hasLibraryInputRole "gcc-lib";
      };
    in
    {
      inherit name checks;
      details = {
        inherit
          missingSymlinks
          realGlibcLoader
          caCertificates
          nixLdLibraryPathInputs
          ;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-fhs = contractLib.mkAssertedJsonCheck "contracts-reports-fhs" [ allValid ] {
    images = perImage;
  };
}
