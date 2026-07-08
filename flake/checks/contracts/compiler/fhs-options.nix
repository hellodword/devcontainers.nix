{
  pkgs,
  lib,
  nixpkgs,
  compiler,
  ...
}:

let
  fixtures = import ./fixtures.nix {
    inherit
      pkgs
      lib
      nixpkgs
      compiler
      ;
  };
  inherit (fixtures)
    caDisabledImage
    caEnvNames
    customDynamicLoader
    customLoaderImage
    customLoaderReport
    extraNixLdLibrariesImage
    fhsDisabledImage
    fhsEnvNames
    fhsOptionsSummary
    fontAliasExpected
    fontAliasImage
    fontAliasReport
    hasAnyAttr
    hasSmokeCase
    lifecycleTasksJsonTask
    lifecycleTimeoutTask
    nixLdDisabledImage
    nixLdEnvNames
    smokeCaseCommandText
    smokeCaseIds
    symlinkSource
    ;
in
{
  contracts-compiler-fhs-options =
    assert !(builtins.hasAttr "runtime/fhs-vscode" fhsDisabledImage.graph.nodes);
    assert builtins.filter (id: lib.hasPrefix "fhs." id) (smokeCaseIds fhsDisabledImage) == [ ];
    assert fhsDisabledImage.fhsRuntime.symlinks == [ ];
    assert
      fhsDisabledImage.fhsRuntime.env == {
        container = { };
        remote = { };
        shell = { };
      };
    assert
      fhsDisabledImage.fhsRuntime.envOrigins == {
        container = { };
        remote = { };
        shell = { };
      };
    assert fhsDisabledImage.fhsRuntime.caCertificates == { };
    assert !(hasAnyAttr fhsEnvNames fhsDisabledImage.env.containerEnv);
    assert nixLdDisabledImage.fhsRuntime.dynamicLoaderMode == "glibc";
    assert !(hasAnyAttr nixLdEnvNames nixLdDisabledImage.fhsRuntime.env.container);
    assert !(hasAnyAttr nixLdEnvNames nixLdDisabledImage.env.containerEnv);
    assert
      symlinkSource "/lib64/ld-linux-x86-64.so.2" nixLdDisabledImage
      == nixLdDisabledImage.fhsRuntime.realGlibcLoader;
    assert hasSmokeCase "fhs.runtime" nixLdDisabledImage;
    assert !(hasSmokeCase "fhs.nix-ld" nixLdDisabledImage);
    assert caDisabledImage.fhsRuntime.caCertificates == { };
    assert !(hasAnyAttr caEnvNames caDisabledImage.fhsRuntime.env.container);
    assert !(hasAnyAttr caEnvNames caDisabledImage.env.containerEnv);
    assert !(hasSmokeCase "fhs.ca-certificates" caDisabledImage);
    assert hasSmokeCase "fhs.runtime" caDisabledImage;
    assert hasSmokeCase "fhs.nix-ld" caDisabledImage;
    assert customLoaderReport.dynamicLoader.target == customDynamicLoader;
    assert
      symlinkSource customDynamicLoader customLoaderImage
      == "${customLoaderImage.config.programs."nix-ld".package}/bin/nix-ld";
    assert lib.hasInfix customDynamicLoader (smokeCaseCommandText "fhs.nix-ld" customLoaderImage);
    assert customLoaderImage.fhsRuntime.nixLdEnv.NIX_LD == customLoaderImage.fhsRuntime.realGlibcLoader;
    assert lib.any (
      entry: (entry.role or null) == "nix-ld-library" && (entry.name or null) == pkgs.zlib.name
    ) extraNixLdLibrariesImage.fhsRuntime.nixLdLibraryPathInputs;
    assert lifecycleTimeoutTask.timeoutSeconds == 123;
    assert lifecycleTasksJsonTask.timeoutSeconds == 123;
    assert fontAliasImage.fonts.report.fontconfig.aliases.Helvetica == fontAliasExpected;
    assert fontAliasReport.fontconfig.aliases.Helvetica == fontAliasExpected;
    pkgs.runCommand "contracts-compiler-fhs-options"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 ${../../../../tests/ci/check-fontconfig-root.py} ${fontAliasImage.fonts.root} ${fontAliasImage.fontconfig-report-json} font-alias-eval
        cp ${fhsOptionsSummary} "$out"
      '';
}
