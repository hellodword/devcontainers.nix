{ pkgs, lib, runtimePackages }:
{
  config,
  compiledEnv,
  compiledMetadata,
  compiledLifecycle,
  compiledVscodeExtensions,
}:
let
  renderJson = value: builtins.toFile "payload.json" (builtins.toJSON value);

  tasksFile = renderJson { tasks = compiledLifecycle.tasks; };
  extensionsFile =
    renderJson {
      extensions = compiledVscodeExtensions.extensions;
      projectionTargets = compiledVscodeExtensions.projectionTargets;
    };

  entrypoint = runtimePackages."devcontainer-entrypoint";
  runtimeTools = [
    runtimePackages."devcontainer-task-runner"
    runtimePackages."vscode-extension-projector"
    runtimePackages."devcontainer-docker-access"
    runtimePackages.devpkg
    runtimePackages."devcontainer-image"
    entrypoint
  ];

  rootfs = pkgs.buildEnv {
    name = "${config.devcontainer.image.name}-rootfs";
    paths = config.devcontainer.packages ++ runtimeTools;
    pathsToLink = [
      "/bin"
      "/share"
    ];
  };

  labels = {
    "devcontainer.metadata" = builtins.toJSON compiledMetadata.label;
  };

  containerConfig = {
    Env =
      lib.mapAttrsToList
        (name: value: "${name}=${value}")
        compiledEnv.containerEnv;
    Entrypoint = [ "/bin/devcontainer-entrypoint" ];
    Cmd = [ "sleep" "infinity" ];
    Labels = labels;
  };

  oci = pkgs.dockerTools.buildLayeredImage {
    name = "devcontainer-${config.devcontainer.image.name}";
    tag =
      if config.devcontainer.image.tags == [ ] then
        "latest"
      else
        builtins.head config.devcontainer.image.tags;
    contents = [ rootfs ];
    config = containerConfig;
    extraCommands = ''
      mkdir -p usr/share/devcontainer/vscode usr/share/devcontainer
      cp ${tasksFile} usr/share/devcontainer/tasks.json
      cp ${extensionsFile} usr/share/devcontainer/vscode/extensions-index.json
      mkdir -p bin usr/bin
      ln -sf ${pkgs.bashInteractive}/bin/bash bin/bash
      ln -sf ${pkgs.bashInteractive}/bin/bash usr/bin/bash
      ln -sf ${pkgs.bashInteractive}/bin/sh bin/sh
      ln -sf ${pkgs.bashInteractive}/bin/sh usr/bin/sh
      ln -sf ${pkgs.coreutils}/bin/env usr/bin/env
      ln -sf ${pkgs.gnutar}/bin/tar usr/bin/tar
      ln -sf ${pkgs.gzip}/bin/gzip usr/bin/gzip
      ln -sf ${pkgs.gnused}/bin/sed usr/bin/sed
      ln -sf ${pkgs.gnugrep}/bin/grep usr/bin/grep
      ln -sf ${pkgs.curl}/bin/curl usr/bin/curl
      ln -sf ${pkgs.wget}/bin/wget usr/bin/wget
      ln -sf ${pkgs.git}/bin/git usr/bin/git
    '';
  };
in
{
  inherit rootfs oci;
}
