{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  moduleTypes = import ../types.nix { inherit lib; };
  inherit (moduleTypes) nonEmptyStringType pathBucketDefinitionType;
  sortedPathBucketDefinitions =
    lib.sort (a: b: if a.order != b.order then a.order < b.order else lib.lessThan a.name b.name)
      (
        lib.mapAttrsToList (
          name: definition:
          definition
          // {
            inherit name;
          }
        ) config.devcontainer.path.bucketDefinitions
      );
in
{
  options.devcontainer.path = {
    bucketDefinitions = mkOption {
      type = types.attrsOf pathBucketDefinitionType;
      default = { };
    };
    segments = mkOption {
      type = types.attrsOf (types.listOf nonEmptyStringType);
      default = { };
    };
    segmentOrigins = mkOption {
      type = types.attrsOf (types.attrsOf (types.listOf nonEmptyStringType));
      default = { };
    };
    order = mkOption {
      type = types.listOf nonEmptyStringType;
      default = [ ];
    };
  };

  config.devcontainer.path = {
    bucketDefinitions = {
      project = {
        order = 0;
        owner = "core/path";
        purpose = "Workspace-local executable paths that should take precedence.";
        segments = [
          "$WORKSPACE/.devcontainer/bin"
          "$WORKSPACE/node_modules/.bin"
          "$WORKSPACE/.venv/bin"
        ];
        segmentOrigins = {
          "$WORKSPACE/.devcontainer/bin" = [ "core.path.project" ];
          "$WORKSPACE/node_modules/.bin" = [ "core.path.project" ];
          "$WORKSPACE/.venv/bin" = [ "core.path.project" ];
        };
      };
      user = {
        order = 10000;
        owner = "core/path";
        purpose = "Per-user package and devcontainer tool paths.";
        segments = [
          "$XDG_DATA_HOME/devcontainer/bin"
          "$XDG_DATA_HOME/nix-profile/bin"
          "$HOME/.nix-profile/bin"
        ];
        segmentOrigins = {
          "$XDG_DATA_HOME/devcontainer/bin" = [ "core.path.user" ];
          "$XDG_DATA_HOME/nix-profile/bin" = [ "core.path.user" ];
          "$HOME/.nix-profile/bin" = [ "core.path.user" ];
        };
      };
      language = {
        order = 20000;
        owner = "core/path";
        purpose = "Language profile executable contributions.";
      };
      system = {
        order = 90000;
        owner = "core/path";
        purpose = "System executable paths.";
        segments = [
          "/usr/local/bin"
          "/usr/bin"
        ];
        segmentOrigins = {
          "/usr/local/bin" = [ "core.path.system" ];
          "/usr/bin" = [ "core.path.system" ];
        };
      };
    };

    order = lib.mkForce (map (bucket: bucket.name) sortedPathBucketDefinitions);
    segments = lib.mkForce (
      lib.mapAttrs (_: definition: definition.segments) config.devcontainer.path.bucketDefinitions
    );
    segmentOrigins = lib.mkForce (
      lib.mapAttrs (_: definition: definition.segmentOrigins) config.devcontainer.path.bucketDefinitions
    );
  };
}
