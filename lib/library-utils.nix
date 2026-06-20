{ lib }:
let
  pathString = path: builtins.unsafeDiscardStringContext (toString path);

  nonEmptyOutputs =
    pkg:
    let
      outputs = pkg.outputs or [ "out" ];
    in
    if outputs == [ ] then [ "out" ] else outputs;

  getOutput = pkg: output: if builtins.hasAttr output pkg then builtins.getAttr output pkg else pkg;
in
rec {
  inherit pathString;

  packageName = pkg: pkg.pname or pkg.name or (builtins.baseNameOf (pathString pkg));

  outputNames = nonEmptyOutputs;

  runtimeOutputName =
    pkg:
    let
      outputs = outputNames pkg;
    in
    if builtins.elem "lib" outputs then
      "lib"
    else if builtins.elem "out" outputs then
      "out"
    else
      builtins.head outputs;

  runtimeOutput = pkg: getOutput pkg (runtimeOutputName pkg);

  buildOutputNames =
    pkg:
    let
      outputs = outputNames pkg;
    in
    lib.unique ([ (runtimeOutputName pkg) ] ++ lib.optional (builtins.elem "dev" outputs) "dev");

  buildOutputs = pkg: map (output: getOutput pkg output) (buildOutputNames pkg);

  uniqueDrvs =
    drvs:
    (lib.foldl'
      (
        acc: drv:
        let
          key = pathString drv;
        in
        if builtins.elem key acc.keys then
          acc
        else
          {
            keys = acc.keys ++ [ key ];
            values = acc.values ++ [ drv ];
          }
      )
      {
        keys = [ ];
        values = [ ];
      }
      drvs
    ).values;

  withoutDrvs =
    excluded: drvs:
    let
      excludedKeys = map pathString excluded;
    in
    builtins.filter (drv: !(builtins.elem (pathString drv) excludedKeys)) drvs;

  packageReport = pkg: {
    package = packageName pkg;
    availableOutputs = outputNames pkg;
    runtimeOutput = runtimeOutputName pkg;
    buildOutputs = buildOutputNames pkg;
  };
}
