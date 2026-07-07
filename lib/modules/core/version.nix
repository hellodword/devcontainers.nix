{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib) mkOption types;

  attrOrNull = name: if builtins.hasAttr name self then builtins.getAttr name self else null;
  firstNonNull = values: lib.findFirst (value: value != null) "unknown" values;

  dirtyRev = attrOrNull "dirtyRev";
  dirtyShortRev = attrOrNull "dirtyShortRev";
  rev = attrOrNull "rev";
  shortRev = attrOrNull "shortRev";

  defaultShortRevision = firstNonNull [
    dirtyShortRev
    shortRev
    dirtyRev
    rev
  ];
  defaultRevision = firstNonNull [
    dirtyRev
    rev
    defaultShortRevision
  ];
  versionFilePath = "/usr/share/devcontainer/version.json";
in
{
  options.devcontainer.image.sourceVersion = {
    version = mkOption {
      type = types.str;
      default = defaultShortRevision;
    };
    revision = mkOption {
      type = types.str;
      default = defaultRevision;
    };
    shortRevision = mkOption {
      type = types.str;
      default = defaultShortRevision;
    };
    dirty = mkOption {
      type = types.bool;
      default = lib.hasSuffix "-dirty" defaultRevision || lib.hasSuffix "-dirty" defaultShortRevision;
    };
    lastModified = mkOption {
      type = types.nullOr types.int;
      default = attrOrNull "lastModified";
    };
  };

  config = {
    environment.variables = {
      DEVCONTAINERS_NIX_VERSION = config.devcontainer.image.sourceVersion.version;
      DEVCONTAINERS_NIX_REVISION = config.devcontainer.image.sourceVersion.revision;
      DEVCONTAINERS_NIX_DIRTY = if config.devcontainer.image.sourceVersion.dirty then "true" else "false";
      DEVCONTAINERS_NIX_VERSION_FILE = versionFilePath;
    };
    environment.variableOrigins = {
      DEVCONTAINERS_NIX_VERSION = [ "core.version" ];
      DEVCONTAINERS_NIX_REVISION = [ "core.version" ];
      DEVCONTAINERS_NIX_DIRTY = [ "core.version" ];
      DEVCONTAINERS_NIX_VERSION_FILE = [ "core.version" ];
    };
  };
}
