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
    bundleResourcesRejected
    cppClangdExtension
    cppCmakeExtension
    cppCoreProfile
    cppLldbExtension
    cppProfileEvalImage
    cppSmokeProfile
    customLocaleCommand
    flutterCoreCaseIds
    hasCompanionTools
    includeCycleRejected
    justExtension
    leafIncludesRejected
    profileIncludeEvalImage
    profileIncludeIds
    profileIncludeLeafA
    pythonExtension
    pythonExtensionIds
    pythonLanguageProfile
    pythonProfileEvalImage
    pythonRuntimeProfile
    shellFeatureCaseIds
    shellFeatureDevpkgCommand
    shellFeatureEvalImage
    shellFeatureInteractiveCommand
    unknownIncludeRejected
    ;
in
{
  contracts-compiler-profiles =
    assert builtins.elem "test/bundle-a" profileIncludeEvalImage.profileReport.rootEnabledProfileIds;
    assert builtins.elem "test/bundle-b" profileIncludeEvalImage.profileReport.rootEnabledProfileIds;
    assert builtins.elem "test/leaf-a" profileIncludeIds;
    assert builtins.elem "test/leaf-b" profileIncludeIds;
    assert builtins.length (builtins.filter (id: id == "test/leaf-a") profileIncludeIds) == 1;
    assert
      profileIncludeEvalImage.profileReport.includeGraph."test/bundle-a" == [
        "test/leaf-a"
        "test/leaf-b"
      ];
    assert
      profileIncludeLeafA.includedBy == [
        "test/bundle-a"
        "test/bundle-b"
      ];
    assert unknownIncludeRejected;
    assert includeCycleRejected;
    assert bundleResourcesRejected;
    assert leafIncludesRejected;
    assert justExtension.origins == [ "language/just" ];
    assert hasCompanionTools justExtension [
      "just"
      "just-lsp"
    ];
    assert !(builtins.elem "ms-python.autopep8" pythonExtensionIds);
    assert builtins.elem "uv" pythonRuntimeProfile.packages;
    assert builtins.elem "pip" pythonRuntimeProfile.packages;
    assert builtins.elem "runtime.python" pythonRuntimeProfile.tests.cases;
    assert builtins.hasAttr "runtime/python" pythonProfileEvalImage.graph.nodes;
    assert builtins.elem "pipx" pythonLanguageProfile.packages;
    assert pythonLanguageProfile.vscode.settings."python.defaultInterpreterPath" == "/usr/bin/python";
    assert builtins.elem "language.python" pythonLanguageProfile.tests.cases;
    assert builtins.hasAttr "language/python" pythonProfileEvalImage.graph.nodes;
    assert !(pythonExtension.native);
    assert builtins.elem "python" pythonExtension.companionTools;
    assert pythonProfileEvalImage.profileReport.validation.companionToolsProvidedByNix;
    assert builtins.hasAttr "runtime/c-env" cppProfileEvalImage.graph.nodes;
    assert builtins.hasAttr "language/cpp/core" cppProfileEvalImage.graph.nodes;
    assert builtins.elem "language.cpp" cppSmokeProfile.tests.cases;
    assert builtins.elem "clangd" cppCoreProfile.provides.commands;
    assert builtins.elem "cmake-language-server" cppCoreProfile.provides.commands;
    assert hasCompanionTools cppClangdExtension [
      "clangd"
      "clang-format"
      "clang-tidy"
    ];
    assert hasCompanionTools cppCmakeExtension [
      "cmake"
      "cmake-language-server"
    ];
    assert cppLldbExtension.native;
    assert cppLldbExtension.sourcePreference == "open-vsx-first";
    assert hasCompanionTools cppLldbExtension [
      "lldb"
      "lldb-dap"
    ];
    assert cppProfileEvalImage.profileReport.validation.companionToolsProvidedByNix;
    assert lib.hasInfix "fr_FR.UTF-8" customLocaleCommand;
    assert lib.hasInfix "fr_FR:fr" customLocaleCommand;
    assert !(lib.hasInfix "en_US.UTF-8" customLocaleCommand);
    assert builtins.elem "shell.interactive" shellFeatureCaseIds;
    assert !(lib.hasInfix "bash-completion" shellFeatureInteractiveCommand);
    assert !(lib.hasInfix "command_not_found_handle" shellFeatureInteractiveCommand);
    assert !(lib.hasInfix "complete -p devpkg" shellFeatureDevpkgCommand);
    assert !(lib.hasInfix "complete -p git" shellFeatureEvalImage.shell.bashrcText);
    assert builtins.elem "language.flutter" flutterCoreCaseIds;
    assert !(builtins.elem "runtime.android-sdk" flutterCoreCaseIds);
    assert !(builtins.elem "runtime.browser-gui-gpu" flutterCoreCaseIds);
    assert !(builtins.elem "language.flutter-rust-bridge" flutterCoreCaseIds);
    pkgs.writeText "contracts-compiler-profiles.json" (
      builtins.toJSON {
        pythonLanguage = pythonLanguageProfile;
        pythonRuntime = pythonRuntimeProfile;
      }
    );
}
