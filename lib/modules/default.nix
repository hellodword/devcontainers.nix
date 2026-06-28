{ lib }:
let
  categories = [
    "core"
    "profiles"
    "editor"
    "programs"
    "toolsets"
    "tools"
    "runtimes"
    "languages"
  ];
  moduleRoot = ./.;
  isModuleFile =
    name: type:
    type == "regular"
    && lib.hasSuffix ".nix" name
    && name != "default.nix"
    && !(lib.hasPrefix "." name)
    && !(lib.hasSuffix "~" name)
    && !(lib.hasSuffix ".bak.nix" name)
    && !(lib.hasSuffix ".orig.nix" name);
  moduleFileNamesFor =
    category:
    lib.sort lib.lessThan (
      builtins.attrNames (lib.filterAttrs isModuleFile (builtins.readDir (moduleRoot + "/${category}")))
    );
  moduleFileNamesByCategory = lib.listToAttrs (
    map (category: lib.nameValuePair category (moduleFileNamesFor category)) categories
  );
  moduleFilesByCategory = lib.mapAttrs (
    category: fileNames: map (fileName: moduleRoot + "/${category}/${fileName}") fileNames
  ) moduleFileNamesByCategory;
in
{
  inherit
    categories
    moduleFilesByCategory
    moduleFileNamesByCategory
    ;
  moduleFileNames = lib.concatMap (category: moduleFileNamesByCategory.${category}) categories;
  allModules = lib.concatMap (category: moduleFilesByCategory.${category}) categories;
}
