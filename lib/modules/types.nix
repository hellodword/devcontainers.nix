{ lib }:
let
  inherit (lib) mkOption types;
  envValueType =
    with types;
    oneOf [
      str
      int
      bool
      path
      package
      (listOf str)
    ];
  nonEmptyStringType = types.addCheck types.str (value: value != "");
  nonEmptyStringListType = types.nonEmptyListOf nonEmptyStringType;
  positiveIntType = types.addCheck types.int (value: value > 0);
  smokeScriptCommandType = types.oneOf [
    nonEmptyStringType
    types.path
  ];
  smokeScriptType = types.submodule {
    options = {
      command = mkOption {
        type = smokeScriptCommandType;
      };
      shell = mkOption {
        type = nonEmptyStringType;
        default = "bash";
      };
      interactive = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };
  libraryPresetNames = [
    "autotools"
    "gtk"
    "gobject-introspection"
    "gstreamer"
    "qt"
    "cgo"
    "rust-bindgen"
  ];
  smokeCaseType = types.submodule {
    options = {
      tags = mkOption {
        type = nonEmptyStringListType;
      };
      scripts = mkOption {
        type = types.nonEmptyListOf smokeScriptType;
      };
      requires = mkOption {
        type = types.listOf nonEmptyStringType;
        default = [ ];
      };
      timeoutSeconds = mkOption {
        type = positiveIntType;
        default = 30;
      };
    };
  };
  lifecycleTaskType = types.submodule {
    options = {
      phase = mkOption {
        type = types.enum [
          "onCreate"
          "postCreate"
          "postStart"
          "postAttach"
        ];
      };
      once = mkOption {
        type = types.bool;
        default = false;
      };
      user = mkOption {
        type = types.enum [ "vscode" ];
        default = "vscode";
      };
      command = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      timeoutSeconds = mkOption {
        type = positiveIntType;
        default = 60;
      };
      needs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };
  vscodeExtensionType = types.submodule (
    { name, ... }:
    {
      options = {
        id = mkOption {
          type = nonEmptyStringType;
          default = name;
        };
        native = mkOption { type = types.bool; };
        bucket = mkOption { type = nonEmptyStringType; };
        companionTools = mkOption { type = types.listOf nonEmptyStringType; };
        projectionOverride = mkOption {
          type = types.nullOr nonEmptyStringType;
          default = null;
        };
        sourcePreference = mkOption {
          type = types.enum [
            "marketplace-first"
            "open-vsx-first"
          ];
          default = "marketplace-first";
        };
        required = mkOption {
          type = types.bool;
          default = true;
        };
        notes = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
      };
    }
  );
  envContributionType = types.submodule {
    options = {
      variables = mkOption {
        type = types.attrsOf envValueType;
        default = { };
      };
      remoteVariables = mkOption {
        type = types.attrsOf envValueType;
        default = { };
      };
      path = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      pathBucket = mkOption {
        type = nonEmptyStringType;
        default = "language";
      };
      aliases = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      shellInit = mkOption {
        type = types.lines;
        default = "";
      };
      interactiveShellInit = mkOption {
        type = types.lines;
        default = "";
      };
    };
  };
  profileType = types.submodule (
    { name, ... }:
    {
      options = {
        id = mkOption {
          type = nonEmptyStringType;
          default = name;
        };
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        kind = mkOption { type = nonEmptyStringType; };
        group = mkOption { type = nonEmptyStringType; };
        packages = mkOption { type = types.listOf types.package; };
        includes = mkOption {
          type = types.listOf nonEmptyStringType;
          default = [ ];
        };
        composition.role = mkOption {
          type = types.enum [
            "leaf"
            "bundle"
          ];
          default = "leaf";
        };
        priority = mkOption { type = types.int; };
        stability = mkOption {
          type = types.enum [
            "very-stable"
            "stable"
            "medium"
            "volatile"
          ];
        };
        sharing = mkOption {
          type = types.enum [
            "global"
            "cross-language"
            "image-family"
            "single-image"
          ];
        };
        securityClass = mkOption {
          type = types.enum [
            "trusted"
            "networked"
          ];
        };
        provides.commands = mkOption {
          type = types.listOf nonEmptyStringType;
          default = [ ];
        };
        vscode = {
          extensions = mkOption {
            type = types.attrsOf vscodeExtensionType;
            default = { };
          };
          settings = mkOption {
            type = types.attrs;
            default = { };
          };
        };
        env = mkOption {
          type = envContributionType;
          default = { };
        };
        libraries.presets = mkOption {
          type = types.listOf (types.enum libraryPresetNames);
          default = [ ];
        };
        lifecycle.tasks = mkOption {
          type = types.attrsOf lifecycleTaskType;
          default = { };
        };
        tests.cases = mkOption {
          type = types.attrsOf smokeCaseType;
          default = { };
        };
      };
    }
  );
  layerBucketDefinitionType = types.submodule {
    options = {
      order = mkOption { type = types.int; };
      owner = mkOption { type = nonEmptyStringType; };
      purpose = mkOption { type = nonEmptyStringType; };
    };
  };
  pathBucketDefinitionType = types.submodule {
    options = {
      order = mkOption { type = types.int; };
      segments = mkOption {
        type = types.listOf nonEmptyStringType;
        default = [ ];
      };
      segmentOrigins = mkOption {
        type = types.attrsOf (types.listOf nonEmptyStringType);
        default = { };
      };
      owner = mkOption { type = nonEmptyStringType; };
      purpose = mkOption { type = nonEmptyStringType; };
    };
  };
in
{
  inherit
    nonEmptyStringType
    smokeCaseType
    profileType
    envContributionType
    lifecycleTaskType
    vscodeExtensionType
    layerBucketDefinitionType
    pathBucketDefinitionType
    libraryPresetNames
    ;
}
