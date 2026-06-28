{
  pkgs,
  lib,
  compiler,
  ...
}:

let
  runtimeHelperNames = builtins.attrNames compiler.runtimeHelpers;
  runtimeHelperListNames = map (helper: helper.name) compiler.runtimeHelperList;
  sortedRuntimeHelperListNames = lib.sort builtins.lessThan runtimeHelperListNames;
  uniqueRuntimeHelperListNames = lib.unique runtimeHelperListNames;
  runtimeHelperOrders = map (helper: helper.order) compiler.runtimeHelperList;
  uniqueRuntimeHelperOrders = lib.unique runtimeHelperOrders;
  runtimeHelperContracts = map (helper: {
    inherit (helper)
      name
      order
      publicPackage
      installInImage
      ;
    checked = helper ? checkName && helper ? checkScript && helper ? checkEnvName;
  }) compiler.runtimeHelperList;
in
{
  contracts-runtime-helpers =
    assert sortedRuntimeHelperListNames == runtimeHelperNames;
    assert builtins.length uniqueRuntimeHelperListNames == builtins.length runtimeHelperListNames;
    assert builtins.length uniqueRuntimeHelperOrders == builtins.length runtimeHelperOrders;
    assert lib.all (
      helper: helper ? package && helper ? publicPackage && helper ? installInImage
    ) compiler.runtimeHelperList;
    pkgs.writeText "contracts-runtime-helpers.json" (
      builtins.toJSON {
        helpers = runtimeHelperContracts;
      }
    );
}
