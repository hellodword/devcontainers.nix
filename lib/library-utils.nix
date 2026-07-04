{ lib }:
let
  displayPathString = path: builtins.unsafeDiscardStringContext (toString path);

  nonEmptyOutputs =
    pkg:
    let
      outputs = pkg.outputs or [ "out" ];
    in
    if outputs == [ ] then [ "out" ] else outputs;

  getOutput = pkg: output: if builtins.hasAttr output pkg then builtins.getAttr output pkg else pkg;
in
rec {
  inherit displayPathString;

  packageName = pkg: pkg.pname or pkg.name or (builtins.baseNameOf (displayPathString pkg));

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
    let
      state =
        lib.foldl'
          (
            acc: drv:
            let
              key = displayPathString drv;
            in
            if builtins.hasAttr key acc.seen then
              acc
            else
              {
                seen = acc.seen // {
                  ${key} = true;
                };
                valuesRev = [ drv ] ++ acc.valuesRev;
              }
          )
          {
            seen = { };
            valuesRev = [ ];
          }
          drvs;
    in
    lib.reverseList state.valuesRev;

  withoutDrvs =
    excluded: drvs:
    let
      excludedKeys = lib.listToAttrs (map (drv: lib.nameValuePair (displayPathString drv) true) excluded);
    in
    builtins.filter (drv: !(builtins.hasAttr (displayPathString drv) excludedKeys)) drvs;

  packageReport = pkg: {
    package = packageName pkg;
    availableOutputs = outputNames pkg;
    runtimeOutput = runtimeOutputName pkg;
    buildOutputs = buildOutputNames pkg;
  };
}
