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
      sourceFor = target: (symlinksByTarget.${target} or { }).source or "";
      missingSymlinks = builtins.filter (
        target: !(builtins.hasAttr target symlinksByTarget)
      ) requiredSymlinkTargets;
      caCertificates = fhs.caCertificates or { };
      realGlibcLoader = fhs.realGlibcLoader or null;
      nixLdLibraryPath = (fhs.nixLdEnv or { }).NIX_LD_LIBRARY_PATH or "";
      checks = {
        enabled = fhs.enabled or false;
        dynamicLoaderMode = (fhs.dynamicLoaderMode or null) == "nix-ld";
        realGlibcLoader =
          contractLib.nonEmptyString realGlibcLoader
          && lib.hasInfix "glibc" realGlibcLoader
          && realGlibcLoader != "/lib64/ld-linux-x86-64.so.2";
        requiredSymlinksPresent = missingSymlinks == [ ];
        caBundle = (caCertificates.bundle or null) == "/etc/ssl/certs/ca-certificates.crt";
        caRoot = lib.hasInfix "ca-certificates" (caCertificates.root or "");
        caSource = lib.hasSuffix "/etc/ssl/certs/ca-certificates.crt" (caCertificates.source or "");
        libcSource = lib.hasInfix "glibc" (sourceFor "/usr/lib/libc.so.6");
        libstdcxxSource = lib.hasInfix "gcc" (sourceFor "/usr/lib/libstdc++.so.6");
        dynamicLoaderSource = lib.hasInfix "nix-ld" (sourceFor "/lib64/ld-linux-x86-64.so.2");
        nixLdEnvLoader = ((fhs.nixLdEnv or { }).NIX_LD or null) == realGlibcLoader;
        nixLdLibraryPathHasRuntimeLibs =
          lib.hasInfix "glibc" nixLdLibraryPath && lib.hasInfix "gcc" nixLdLibraryPath;
      };
    in
    {
      inherit name checks;
      details = {
        inherit missingSymlinks realGlibcLoader caCertificates;
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
