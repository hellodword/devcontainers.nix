{ lib, ... }:
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
        type = types.enum [ "very-stable" "stable" "medium" "volatile" ];
        default = "stable";
      };
      sharing = mkOption {
        type = types.enum [ "global" "cross-language" "image-family" "single-image" ];
        default = "global";
      };
      priority = mkOption {
        type = types.int;
        default = 50;
      };
      securityClass = mkOption {
        type = types.enum [ "trusted" "networked" "docker-daemon-access" ];
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
  lifecycleTaskType = types.submodule {
    options = {
      phase = mkOption {
        type = types.enum [ "onCreate" "postCreate" "postStart" "postAttach" ];
      };
      once = mkOption {
        type = types.bool;
        default = false;
      };
      user = mkOption {
        type = types.str;
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
      maxCompressedLayerSize = mkOption {
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
      remoteUser = mkOption {
        type = types.str;
        default = "vscode";
      };
      containerUser = mkOption {
        type = types.str;
        default = "vscode";
      };
      updateRemoteUserUID = mkOption {
        type = types.bool;
        default = false;
      };
    };

    env = {
      container = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      remote = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      shell = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };

    path = {
      segments = mkOption {
        type = types.attrsOf (types.listOf types.str);
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
            type = types.enum [ "onCreate" "postCreate" "postStart" "postAttach" ];
            default = "postCreate";
          };
          mode = mkOption {
            type = types.str;
            default = "symlink-or-copy";
          };
          targets = mkOption {
            type = types.listOf types.str;
            default = [
              "$HOME/.vscode-server/extensions"
              "$HOME/.vscode-server-insiders/extensions"
              "$HOME/.vscode-remote/extensions"
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

    dockerAccess = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      packages = mkOption {
        type = types.listOf types.package;
        default = [ ];
      };
      mounts = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      containerEnv = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      defaultMode = mkOption {
        type = types.str;
        default = "host-socket";
      };
      modes = {
        hostSocket.enable = mkOption {
          type = types.bool;
          default = true;
        };
        hostSocket.mount = mkOption {
          type = types.str;
          default = "type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock";
        };
        remoteTcpTls.enable = mkOption {
          type = types.bool;
          default = true;
        };
        remoteTcpTls.host = mkOption {
          type = types.str;
          default = "docker.example.internal:2376";
        };
        remoteTcpTls.certMount = mkOption {
          type = types.str;
          default = "type=bind,source=${localEnv:HOME}/.docker/devcontainer-certs,target=/run/docker-certs,readonly";
        };
      };
    };

    tests.smoke = mkOption {
      type = types.listOf smokeTestType;
      default = [ ];
    };

    toolsets = {
      foundation.enable = mkOption { type = types.bool; default = true; };
      sourceControl.enable = mkOption { type = types.bool; default = true; };
      fetchArchive.enable = mkOption { type = types.bool; default = true; };
      searchNavigation.enable = mkOption { type = types.bool; default = true; };
      inspectDebug.enable = mkOption { type = types.bool; default = true; };
      workflowFormat.enable = mkOption { type = types.bool; default = true; };
      dataNetwork.enable = mkOption { type = types.bool; default = false; };
    };

    runtimes = {
      cEnv.enable = mkOption { type = types.bool; default = false; };
      python.enable = mkOption { type = types.bool; default = false; };
      nodejs.enable = mkOption { type = types.bool; default = false; };
    };

    languages = {
      python.enable = mkOption { type = types.bool; default = false; };
      nodejs.enable = mkOption { type = types.bool; default = false; };
      go.enable = mkOption { type = types.bool; default = false; };
      rust.enable = mkOption { type = types.bool; default = false; };
      flutter.enable = mkOption { type = types.bool; default = false; };
    };
  };
}
