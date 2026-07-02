{ inputs }:

let
  # builtins.toJSON coerces attrsets containing outPath into path strings.
  renderJson =
    value:
    if builtins.isAttrs value then
      "{"
      + builtins.concatStringsSep "," (
        map (name: "${builtins.toJSON name}:${renderJson (builtins.getAttr name value)}") (
          builtins.attrNames value
        )
      )
      + "}"
    else if builtins.isList value then
      "[" + builtins.concatStringsSep "," (map renderJson value) + "]"
    else
      builtins.toJSON value;
  maybe = name: input: if builtins.hasAttr name input then builtins.getAttr name input else null;
  maybeString =
    name: input:
    let
      value = maybe name input;
    in
    if value == null then null else toString value;
  mkInput = input: {
    rev = maybe "rev" input;
    shortRev = maybe "shortRev" input;
    lastModified = maybe "lastModified" input;
    lastModifiedDate = maybe "lastModifiedDate" input;
    narHash = maybe "narHash" input;
    outPath = maybeString "outPath" input;
  };
in
let
  manifest = {
    schemaVersion = 1;
    inputs = {
      nixpkgs = mkInput (inputs.nixpkgs);
    };
  };
in
{
  inherit manifest;
  json = renderJson manifest;
}
