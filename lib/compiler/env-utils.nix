{ lib }:
let
  isVarStart = char: builtins.match "[A-Za-z_]" char != null;
  isVarChar = char: builtins.match "[A-Za-z0-9_]" char != null;
  validVarName = name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null;
  charAt = value: index: builtins.substring index 1 value;

  stringifyEnvValue =
    {
      value,
      pathSeparator ? ":",
    }:
    if builtins.isBool value then
      if value then "1" else "0"
    else if builtins.isInt value then
      toString value
    else if builtins.isList value then
      lib.concatStringsSep pathSeparator (
        map (
          entry:
          stringifyEnvValue {
            inherit pathSeparator;
            value = entry;
          }
        ) value
      )
    else
      toString value;

  normalizeEnv =
    {
      env,
      pathSeparator,
    }:
    lib.mapAttrs (_: value: stringifyEnvValue { inherit value pathSeparator; }) env;

  takeVarName =
    value: start:
    let
      length = builtins.stringLength value;
      go = index: if index < length && isVarChar (charAt value index) then go (index + 1) else index;
      end = go start;
    in
    {
      name = builtins.substring start (end - start) value;
      inherit end;
    };

  findClosingBrace =
    value: start:
    let
      length = builtins.stringLength value;
      go =
        index:
        if index >= length then
          null
        else if charAt value index == "}" then
          index
        else
          go (index + 1);
    in
    go start;

  expandString =
    env: rawValue:
    let
      value = stringifyEnvValue { value = rawValue; };
      length = builtins.stringLength value;
      go =
        index: parts: references:
        if index >= length then
          {
            value = lib.concatStrings (lib.reverseList parts);
            references = lib.unique references;
          }
        else
          let
            char = charAt value index;
          in
          if char != "$" || index + 1 >= length then
            go (index + 1) ([ char ] ++ parts) references
          else
            let
              next = charAt value (index + 1);
            in
            if next == "{" then
              let
                close = findClosingBrace value (index + 2);
              in
              if close == null then
                go (index + 1) ([ char ] ++ parts) references
              else
                let
                  name = builtins.substring (index + 2) (close - index - 2) value;
                  original = builtins.substring index (close - index + 1) value;
                  known = validVarName name && builtins.hasAttr name env;
                  replacement = if known then builtins.getAttr name env else original;
                  refs = if known then references ++ [ name ] else references;
                in
                go (close + 1) ([ replacement ] ++ parts) refs
            else if isVarStart next then
              let
                parsed = takeVarName value (index + 1);
                known = builtins.hasAttr parsed.name env;
                original = builtins.substring index (parsed.end - index) value;
                replacement = if known then builtins.getAttr parsed.name env else original;
                refs = if known then references ++ [ parsed.name ] else references;
              in
              go parsed.end ([ replacement ] ++ parts) refs
            else
              go (index + 1) ([ char ] ++ parts) references;
    in
    go 0 [ ] [ ];

  referencesTo =
    names: env: value:
    builtins.filter (name: builtins.elem name names) (expandString env value).references;

  unresolvedReferences =
    names: env:
    lib.unique (lib.concatLists (lib.mapAttrsToList (_: value: referencesTo names env value) env));

  formatReferenceError =
    {
      scope,
      maxDepth,
      references,
      kind,
    }:
    "environment expansion ${kind} in ${scope}; max depth ${toString maxDepth}; unresolved references: ${lib.concatStringsSep ", " references}";
in
rec {
  inherit stringifyEnvValue;

  expandValue =
    {
      env,
      value,
      pathSeparator ? ":",
    }:
    let
      normalizedEnv = normalizeEnv { inherit env pathSeparator; };
    in
    (expandString normalizedEnv (stringifyEnvValue {
      inherit value pathSeparator;
    })).value;

  expandEnv =
    {
      env,
      context ? { },
      maxDepth ? 8,
      pathSeparator ? ":",
      scope ? "environment",
    }:
    let
      inputNames = builtins.attrNames env;
      normalizedContext = normalizeEnv {
        env = context;
        inherit pathSeparator;
      };
      normalizedEnv = normalizeEnv {
        inherit env pathSeparator;
      };
      step =
        current:
        let
          expansionEnv = normalizedContext // current;
        in
        lib.mapAttrs (_: value: (expandString expansionEnv value).value) current;
      refsFor = current: unresolvedReferences inputNames (normalizedContext // current);
      go =
        depth: current:
        let
          next = step current;
          refs = refsFor next;
        in
        if next == current then
          if refs == [ ] then
            current
          else
            builtins.throw (formatReferenceError {
              inherit scope maxDepth;
              references = refs;
              kind = "contains a cycle";
            })
        else if depth >= maxDepth then
          builtins.throw (formatReferenceError {
            inherit scope maxDepth;
            references = refs;
            kind = "exceeded max depth";
          })
        else
          go (depth + 1) next;
    in
    go 1 normalizedEnv;

  expandEnvWithContext =
    {
      context,
      env,
      maxDepth ? 8,
      pathSeparator ? ":",
      scope ? "environment",
    }:
    expandEnv {
      inherit
        context
        env
        maxDepth
        pathSeparator
        scope
        ;
    };
}
