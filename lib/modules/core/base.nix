{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  moduleTypes = import ../types.nix { inherit lib; };
  inherit (moduleTypes)
    nonEmptyStringType
    profileType
    smokeCaseType
    layerBucketDefinitionType
    ;
  graphNodeType = types.submodule {
    options = {
      kind = mkOption { type = types.str; };
      paths = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
      files = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      group = mkOption { type = nonEmptyStringType; };
      target = mkOption {
        type = types.str;
        default = "host";
      };
      stability = mkOption {
        type = types.enum [
          "very-stable"
          "stable"
          "medium"
          "volatile"
        ];
        default = "stable";
      };
      sharing = mkOption {
        type = types.enum [
          "global"
          "cross-language"
          "image-family"
          "single-image"
        ];
        default = "global";
      };
      priority = mkOption {
        type = types.int;
        default = 50;
      };
      securityClass = mkOption {
        type = types.enum [
          "trusted"
          "networked"
        ];
        default = "trusted";
      };
    };
  };
  sortedLayerBucketDefinitions =
    lib.sort (a: b: if a.order != b.order then a.order < b.order else lib.lessThan a.name b.name)
      (
        lib.mapAttrsToList (
          name: definition:
          definition
          // {
            inherit name;
          }
        ) config.devcontainer.layers.bucketDefinitions
      );
in
{
  options.devcontainer = {
    image = {
      name = mkOption { type = types.str; };
      family = mkOption {
        type = types.str;
        default = config.devcontainer.image.name;
      };
      tags = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      architectures = mkOption {
        type = types.listOf types.str;
        default = [ "linux/amd64" ];
      };
    };

    graph.nodes = mkOption {
      type = types.attrsOf graphNodeType;
      default = { };
    };

    layers = {
      strategy = mkOption {
        type = types.str;
        default = "balanced";
      };
      max = mkOption {
        type = types.int;
        default = 100;
      };
      reserve = mkOption {
        type = types.int;
        default = 20;
      };
      maxLayerSize = mkOption {
        type = types.str;
        default = "8GiB";
      };
      bucketDefinitions = mkOption {
        type = types.attrsOf layerBucketDefinitionType;
        default = { };
      };
      buckets = mkOption {
        type = types.listOf nonEmptyStringType;
        default = [ ];
      };
    };

    profiles = mkOption {
      type = types.attrsOf profileType;
      default = { };
    };

    tests.cases = mkOption {
      type = types.attrsOf smokeCaseType;
      default = { };
    };
  };

  config = {
    devcontainer.layers.bucketDefinitions = {
      "95-dynamic-package-runtime" = {
        order = 37;
        owner = "core/base";
        purpose = "Dynamic packages and late image package materialization.";
      };
      "99-fallback" = {
        order = 38;
        owner = "core/base";
        purpose = "Fallback bucket for image-specific profiles and test profiles.";
      };
    };

    devcontainer.layers.buckets = lib.mkForce (map (bucket: bucket.name) sortedLayerBucketDefinitions);

    devcontainer.metadata.snippets = [
      {
        init = true;
        hostRequirements = {
          cpus = 2;
          memory = "4gb";
        };
      }
    ];
  };
}
