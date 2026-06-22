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
  nixSettingValueType =
    with types;
    oneOf [
      str
      int
      bool
      (listOf str)
    ];
  nonEmptyStringType = types.addCheck types.str (value: value != "");
  nonEmptyStringListType = types.addCheck (types.listOf types.str) (value: value != [ ]);
  etcEntryType = types.submodule (
    { name, ... }:
    {
      options = {
        target = mkOption {
          type = types.str;
          default = name;
        };
        text = mkOption {
          type = types.nullOr types.lines;
          default = null;
        };
        source = mkOption {
          type = types.nullOr (
            types.oneOf [
              types.str
              types.path
              types.package
            ]
          );
          default = null;
        };
        mode = mkOption {
          type = types.str;
          default = "0644";
        };
        uid = mkOption {
          type = types.int;
          default = 0;
        };
        gid = mkOption {
          type = types.int;
          default = 0;
        };
      };
    }
  );
  knownHostType = types.submodule (
    { name, ... }:
    {
      options = {
        hostNames = mkOption {
          type = nonEmptyStringListType;
          default = [ name ];
        };
        publicKey = mkOption { type = nonEmptyStringType; };
        certAuthority = mkOption {
          type = types.bool;
          default = false;
        };
      };
    }
  );
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
        lifecycle.tasks = mkOption {
          type = types.attrsOf lifecycleTaskType;
          default = { };
        };
        tests.smoke = mkOption {
          type = types.listOf smokeTestType;
          default = [ ];
        };
      };
    }
  );
in
{
  options = {
    environment = {
      systemPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
      pathsToLink = mkOption {
        type = types.listOf types.str;
        default = [
          "/bin"
          "/include"
          "/lib"
          "/lib64"
          "/libexec"
          "/share"
          "/etc"
        ];
      };
      extraOutputsToInstall = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      etc = mkOption {
        type = types.attrsOf etcEntryType;
        default = { };
      };
      variables = mkOption {
        type = types.attrsOf envValueType;
        default = { };
      };
      variableOrigins = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
      };
      shellAliases = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      shellAliasOrigins = mkOption {
        type = types.attrsOf (types.listOf types.str);
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

    i18n = {
      defaultLocale = mkOption {
        type = types.str;
        default = "en_US.UTF-8";
      };
      extraLocaleSettings = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      glibcLocales = mkOption {
        type = types.package;
        default = pkgs.glibcLocales;
      };
      supportedLocales = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      language = mkOption {
        type = types.str;
        default = "en_US:en";
      };
    };

    time.timeZone = mkOption {
      type = types.nullOr types.str;
      default = "Etc/UTC";
    };

    security = {
      pki = {
        installCACerts = mkOption {
          type = types.bool;
          default = true;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.dockerTools.caCertificates;
        };
        certificates = mkOption {
          type = types.listOf types.lines;
          default = [ ];
        };
        certificateFiles = mkOption {
          type = types.listOf types.path;
          default = [ ];
        };
        blacklist = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
      sudo.enable = mkOption {
        type = types.enum [ false ];
        default = false;
      };
      pam.enable = mkOption {
        type = types.enum [ false ];
        default = false;
      };
      polkit.enable = mkOption {
        type = types.enum [ false ];
        default = false;
      };
    };

    programs = {
      bash = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
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
          default = config.programs.nix-index.enable;
        };
      };

      git = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.git;
        };
        lfs.enable = mkOption {
          type = types.bool;
          default = false;
        };
        config = mkOption {
          type = types.attrs;
          default = { };
        };
        extraConfig = mkOption {
          type = types.lines;
          default = "";
        };
        attributes = mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        extraAttributes = mkOption {
          type = types.lines;
          default = "";
        };
        prompt.enable = mkOption {
          type = types.bool;
          default = true;
        };
      };

      ssh = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.openssh;
        };
        knownHosts = mkOption {
          type = types.attrsOf knownHostType;
          default = { };
        };
        knownHostsFiles = mkOption {
          type = types.listOf types.path;
          default = [ ];
        };
        extraConfig = mkOption {
          type = types.lines;
          default = "";
        };
        algorithms = {
          kexAlgorithms = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          hostKeyAlgorithms = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          ciphers = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          macs = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
        };
        forwardX11 = mkOption {
          type = types.bool;
          default = false;
        };
      };

      nix-index = {
        enable = mkOption {
          type = types.bool;
          default = false;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.nix-index-with-db;
        };
        comma.enable = mkOption {
          type = types.bool;
          default = true;
        };
        comma.package = mkOption {
          type = types.nullOr types.package;
          default = if builtins.hasAttr "comma-with-db" pkgs then pkgs.comma-with-db else null;
        };
      };

      nix-ld = {
        enable = mkOption {
          type = types.bool;
          default = true;
        };
        package = mkOption {
          type = types.package;
          default = pkgs.nix-ld;
        };
        libraries = mkOption {
          type = types.listOf types.package;
          default = [ ];
        };
        dynamicLoader = {
          x86_64.path = mkOption {
            type = types.str;
            default = "/lib64/ld-linux-x86-64.so.2";
          };
          aarch64.path = mkOption {
            type = types.str;
            default = "/lib/ld-linux-aarch64.so.1";
          };
        };
      };
    };

    nix = {
      package = mkOption {
        type = types.package;
        default = pkgs.nix;
      };
      settings = mkOption {
        type = types.attrsOf nixSettingValueType;
        default = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
        };
      };
      extraOptions = mkOption {
        type = types.lines;
        default = "";
      };
    };

    devcontainer = {
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

      gui.forwarding.enable = mkOption {
        type = types.bool;
        default = true;
      };

      profiles = mkOption {
        type = types.attrsOf profileType;
        default = { };
      };

      remoteEnv = mkOption {
        type = types.attrsOf envValueType;
        default = { };
      };
      remoteEnvOrigins = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = { };
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
        };
      };

      vscode = {
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
        nixIndex.comma.enable = mkOption {
          type = types.bool;
          default = true;
        };
      };

      runtimes = {
        python = {
          package = mkOption {
            type = types.nullOr types.package;
            default = null;
          };
        };
        nodejs = {
          package = mkOption {
            type = types.nullOr types.package;
            default = null;
          };
        };
      };

      languages = {
        python = {
          packageSet = mkOption {
            type = types.nullOr types.attrs;
            default = null;
          };
        };
        go = {
          package = mkOption {
            type = types.nullOr types.package;
            default = null;
          };
        };
        rust = {
          toolchain = mkOption {
            type = types.nullOr types.package;
            default = null;
          };
        };
      };
    };
  };
}
