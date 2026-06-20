{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
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
      group = mkOption { type = types.str; };
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
  smokeTestType = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      command = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };
  fontAliasType = types.submodule {
    options = {
      binding = mkOption {
        type = types.enum [
          "same"
          "weak"
          "strong"
        ];
        default = "same";
      };
      prefer = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      accept = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      default = mkOption {
        type = types.listOf types.str;
        default = [ ];
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
        type = types.int;
        default = 60;
      };
      needs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };
  };
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

    packages = mkOption {
      type = types.listOf types.package;
      default = [ ];
    };

    fonts = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      packages = mkOption {
        type = types.listOf types.package;
        default = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-cjk-serif
          noto-fonts-color-emoji
        ];
      };
      fontconfig = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.fontconfig;
        };
        includeUserConf = mkOption {
          type = types.bool;
          default = true;
        };
        localConf = mkOption {
          type = types.lines;
          default = "";
        };
        defaultFonts = {
          sansSerif = mkOption {
            type = types.listOf types.str;
            default = [
              "Noto Sans CJK SC"
              "Noto Sans"
            ];
          };
          serif = mkOption {
            type = types.listOf types.str;
            default = [
              "Noto Serif CJK SC"
              "Noto Serif"
            ];
          };
          monospace = mkOption {
            type = types.listOf types.str;
            default = [
              "Noto Sans Mono CJK SC"
              "Noto Sans Mono"
            ];
          };
          emoji = mkOption {
            type = types.listOf types.str;
            default = [ "Noto Color Emoji" ];
          };
        };
        aliases = mkOption {
          type = types.attrsOf fontAliasType;
          default = { };
        };
      };
    };

    libraries = {
      runtime = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
      build = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
      exportLdLibraryPath = mkOption {
        type = types.bool;
        default = false;
      };
      ccWrapperFlags = mkOption {
        type = types.bool;
        default = true;
      };
      presets = mkOption {
        type = types.listOf (
          types.enum [
            "autotools"
            "gtk"
            "gobject-introspection"
            "gstreamer"
            "qt"
            "cgo"
            "rust-bindgen"
          ]
        );
        default = [ ];
      };
      dynamicRuntimeProfile = mkOption {
        type = types.str;
        default = "$XDG_DATA_HOME/devpkg/runtime-libraries/profile";
      };
      dynamicBuildProfile = mkOption {
        type = types.str;
        default = "$XDG_DATA_HOME/devpkg/build-libraries/profile";
      };
    };

    locale = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      lang = mkOption {
        type = types.str;
        default = "en_US.UTF-8";
      };
      language = mkOption {
        type = types.str;
        default = "en_US:en";
      };
      lc = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      lcAll = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      archive = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.glibcLocales;
        };
      };
    };

    shell = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      aliases = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      aliasOrigins = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
      bash = {
        prompt.enable = mkOption {
          type = types.bool;
          default = true;
        };
        history.enable = mkOption {
          type = types.bool;
          default = true;
        };
        completion.enable = mkOption {
          type = types.bool;
          default = true;
        };
        commandNotFound.enable = mkOption {
          type = types.bool;
          default = config.devcontainer.toolsets.nixIndex.enable;
        };
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
      buckets = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };

    metadata.snippets = mkOption {
      type = types.listOf types.attrs;
      default = [ ];
    };

    user = {
      name = mkOption {
        type = types.enum [ "vscode" ];
        default = "vscode";
      };
      uid = mkOption {
        type = types.enum [ 1000 ];
        default = 1000;
      };
      group = mkOption {
        type = types.enum [ "vscode" ];
        default = "vscode";
      };
      gid = mkOption {
        type = types.enum [ 1000 ];
        default = 1000;
      };
      home = mkOption {
        type = types.enum [ "/home/vscode" ];
        default = "/home/vscode";
      };
      shell = mkOption {
        type = types.enum [ "/bin/bash" ];
        default = "/bin/bash";
      };
      remoteUser = mkOption {
        type = types.enum [ "vscode" ];
        default = "vscode";
      };
      containerUser = mkOption {
        type = types.enum [ "vscode" ];
        default = "vscode";
      };
      updateRemoteUserUID = mkOption {
        type = types.enum [ false ];
        default = false;
      };
    };

    filesystem = {
      osRelease = {
        name = mkOption {
          type = types.str;
          default = "devcontainer-nix";
        };
        id = mkOption {
          type = types.str;
          default = "devcontainer-nix";
        };
        versionId = mkOption {
          type = types.str;
          default = "26.05";
        };
        prettyName = mkOption {
          type = types.str;
          default = "Devcontainer Nix 26.05";
        };
      };
      directories = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              mode = mkOption { type = types.str; };
              uid = mkOption { type = types.int; };
              gid = mkOption { type = types.int; };
            };
          }
        );
        default = { };
      };
    };

    env = {
      container = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      origins.container = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
      remote = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      origins.remote = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
      shell = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      origins.shell = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
    };

    path = {
      segments = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
      segmentOrigins = mkOption {
        type = types.attrsOf (types.attrsOf (types.listOf types.str));
        default = { };
      };
      order = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
    };

    compat = {
      fhsRuntime = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        binSh = mkOption {
          type = types.bool;
          default = true;
        };
        binBash = mkOption {
          type = types.bool;
          default = true;
        };
        usrBinEnv = mkOption {
          type = types.bool;
          default = true;
        };
        usrBinCoreTools = mkOption {
          type = types.bool;
          default = true;
        };
        etcOsRelease = mkOption {
          type = types.bool;
          default = true;
        };
        caCertificates = mkOption {
          type = types.bool;
          default = true;
        };
        dynamicLoader = {
          mode = mkOption {
            type = types.str;
            default = "nix-ld";
          };
          x86_64.path = mkOption {
            type = types.str;
            default = "/lib64/ld-linux-x86-64.so.2";
          };
          aarch64.path = mkOption {
            type = types.str;
            default = "/lib/ld-linux-aarch64.so.1";
          };
        };
        nixLdLibraries = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
      };
    };

    vscode = {
      extensions = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      settings = mkOption {
        type = types.attrs;
        default = { };
      };
      preinstall = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        source = mkOption {
          type = types.str;
          default = "nix-vscode-extensions";
        };
        store = {
          extensionsPath = mkOption {
            type = types.str;
            default = "/usr/share/devcontainer/vscode/extensions";
          };
          vsixPath = mkOption {
            type = types.str;
            default = "/usr/share/devcontainer/vscode/vsix";
          };
          indexPath = mkOption {
            type = types.str;
            default = "/usr/share/devcontainer/vscode/extensions-index.json";
          };
        };
        projection = {
          enable = mkOption {
            type = types.bool;
            default = true;
          };
          phase = mkOption {
            type = types.enum [
              "onCreate"
              "postCreate"
              "postStart"
              "postAttach"
            ];
            default = "postCreate";
          };
          mode = mkOption {
            type = types.str;
            default = "symlink-or-copy";
          };
          targets = mkOption {
            type = types.listOf types.str;
            default = [
              "${config.devcontainer.user.home}/.vscode-server/extensions"
              "${config.devcontainer.user.home}/.vscode-server-insiders/extensions"
              "${config.devcontainer.user.home}/.vscode-remote/extensions"
            ];
          };
        };
        validation = {
          nativeBinaries = mkOption {
            type = types.bool;
            default = true;
          };
          fhsRuntime = mkOption {
            type = types.bool;
            default = true;
          };
          noNetworkDuringProjection = mkOption {
            type = types.bool;
            default = true;
          };
        };
      };
    };

    lifecycle.tasks = mkOption {
      type = types.attrsOf lifecycleTaskType;
      default = { };
    };

    tests.smoke = mkOption {
      type = types.listOf smokeTestType;
      default = [ ];
    };

    toolsets = {
      foundation.enable = mkOption {
        type = types.bool;
        default = true;
      };
      sourceControl.enable = mkOption {
        type = types.bool;
        default = true;
      };
      fetchArchive.enable = mkOption {
        type = types.bool;
        default = true;
      };
      searchNavigation.enable = mkOption {
        type = types.bool;
        default = true;
      };
      inspectDebug.enable = mkOption {
        type = types.bool;
        default = true;
      };
      workflowFormat.enable = mkOption {
        type = types.bool;
        default = true;
      };
      dataNetwork.enable = mkOption {
        type = types.bool;
        default = false;
      };
      dockerClient.enable = mkOption {
        type = types.bool;
        default = true;
      };
      agents.enable = mkOption {
        type = types.bool;
        default = true;
      };
      nixIndex.enable = mkOption {
        type = types.bool;
        default = true;
      };
      nixIndex.comma.enable = mkOption {
        type = types.bool;
        default = true;
      };
    };

    runtimes = {
      cEnv.enable = mkOption {
        type = types.bool;
        default = false;
      };
      python = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        package = mkOption {
          type = types.nullOr types.package;
          default = null;
        };
      };
      nodejs = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        package = mkOption {
          type = types.nullOr types.package;
          default = null;
        };
      };
    };

    languages = {
      python = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        packageSet = mkOption {
          type = types.nullOr types.attrs;
          default = null;
        };
      };
      nodejs.enable = mkOption {
        type = types.bool;
        default = false;
      };
      go = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        package = mkOption {
          type = types.nullOr types.package;
          default = null;
        };
      };
      rust = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        toolchain = mkOption {
          type = types.nullOr types.package;
          default = null;
        };
      };
      flutter.enable = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };
}
