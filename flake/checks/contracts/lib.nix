{
  lib,
  pkgs ? null,
}:

let
  requirePkgs =
    if pkgs == null then throw "contract helper requires pkgs for derivation builders" else pkgs;

  sortStrings = lib.sort builtins.lessThan;

  missingFrom = expected: actual: builtins.filter (value: !(builtins.elem value actual)) expected;

  normalizeSet = values: sortStrings (lib.unique values);
in
rec {
  nonEmptyString = value: builtins.isString value && value != "";

  duplicateValues =
    values:
    lib.unique (
      builtins.filter (
        value: builtins.length (builtins.filter (candidate: candidate == value) values) > 1
      ) values
    );

  sameSet = left: right: normalizeSet left == normalizeSet right;

  setDiff = expected: actual: {
    missing = sortStrings (missingFrom expected actual);
    unexpected = sortStrings (missingFrom actual expected);
    same = sameSet expected actual;
  };

  requireAll = required: actual: (setDiff required actual).missing == [ ];

  findBy =
    predicate: description: values:
    lib.findFirst predicate (throw "missing ${description}") values;

  findById = id: values: findBy (value: (value.id or null) == id) "id ${id}" values;

  requireAttrs = names: attrs: requireAll names (builtins.attrNames attrs);

  mkJsonCheck = name: payload: requirePkgs.writeText "${name}.json" (builtins.toJSON payload);

  mkAssertedJsonCheck =
    name: assertions: payload:
    assert lib.all (assertion: assertion) assertions;
    mkJsonCheck name payload;

  mkRunCommand =
    name: attrs: script:
    requirePkgs.runCommand name attrs script;

  mkPerImageCheck =
    prefix: images: build:
    lib.mapAttrs' (name: image: lib.nameValuePair "${prefix}-${name}" (build name image)) images;
}
