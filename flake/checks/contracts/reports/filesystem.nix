{
  lib,
  images,
  contractLib,
  ...
}:

let
  requiredEtcPaths = [
    "/etc/nix/nix.conf"
    "/etc/ssl/certs/ca-certificates.crt"
    "/etc/localtime"
    "/etc/zoneinfo"
    "/etc/gitconfig"
    "/etc/ssh/ssh_config"
    "/etc/ssh/ssh_known_hosts"
  ];
  requiredShellFiles = [
    "/etc/profile"
    "/etc/bashrc"
    "/etc/bash.bashrc"
    "/home/vscode/.bashrc"
  ];
  requiredDirectories = [
    "/etc/xdg"
    "/home/vscode"
    "/tmp"
    "/var"
    "/var/cache"
    "/var/lib"
    "/var/log"
    "/var/tmp"
    "/run/user/1000"
    "/workspaces"
    "/home/vscode/.codex"
    "/home/vscode/.local/state/bash"
  ];
  nixDatabaseDirs = [
    "/nix"
    "/nix/store"
    "/nix/var/nix"
    "/nix/var/nix/db"
  ];
  requiredNixpkgsConfigSettings = [
    "allowUnfree = true;"
    "android_sdk.accept_license = true;"
    "oraclejdk.accept_license = true;"
    "allowUnsupportedSystem = true;"
  ];
  projectionSuffix = "/extensions";
  projectionSuffixLength = builtins.stringLength projectionSuffix;
  settingsPathForTarget =
    target:
    let
      root =
        if lib.hasSuffix projectionSuffix target then
          builtins.substring 0 ((builtins.stringLength target) - projectionSuffixLength) target
        else
          target;
    in
    "${root}/data/Machine/settings.json";
  perImage = lib.mapAttrsToList (
    name: image:
    let
      fs = image.filesystem;
      user = image.config.devcontainer.user;
      directoriesByPath = lib.listToAttrs (
        map (entry: lib.nameValuePair entry.path entry) fs.directories
      );
      dir = path: directoriesByPath.${path} or { };
      etcPaths = map (entry: entry.path) fs.etcFiles;
      missingEtc = builtins.filter (path: !(builtins.elem path etcPaths)) requiredEtcPaths;
      missingShellFiles = builtins.filter (path: !(builtins.elem path fs.shellFiles)) requiredShellFiles;
      missingDirectories = builtins.filter (
        path: !(builtins.hasAttr path directoriesByPath)
      ) requiredDirectories;
      nixDatabaseDirsPresent = builtins.filter (
        path: builtins.hasAttr path directoriesByPath
      ) nixDatabaseDirs;
      symlinkTarget =
        path: (lib.findFirst (entry: entry.path == path) { target = null; } fs.symlinks).target;
      projectionTargets = image.vscodeExtensions.projectionTargets;
      expectedMachineSettings = lib.sort lib.lessThan (map settingsPathForTarget projectionTargets);
      machineSettings = fs.vscodeMachineSettings;
      machineSettingPaths = map (entry: entry.settingsPath) (machineSettings.paths or [ ]);
      invalidMachineSettingEntries = builtins.filter (
        entry:
        (entry.owner or null) != "root:root"
        || (entry.rootMode or null) != "1777"
        || (entry.dataMode or null) != "1777"
        || (entry.machineMode or null) != "1777"
        || (entry.settingsMode or null) != "0444"
      ) (machineSettings.paths or [ ]);
      checks = {
        userName = user.name == "vscode";
        userUid = user.uid == 1000;
        userGroup = user.group == "vscode";
        userGid = user.gid == 1000;
        userHome = user.home == "/home/vscode";
        userShell = user.shell == "/bin/bash";
        userRemote = user.remoteUser == "vscode";
        userContainer = user.containerUser == "vscode";
        nixpkgsConfigPath = fs.nixpkgsConfig.path == "/etc/nixpkgs/config.nix";
        nixpkgsConfigSettings = lib.all (
          setting: lib.hasInfix setting fs.nixpkgsConfig.text
        ) requiredNixpkgsConfigSettings;
        shellFiles = missingShellFiles == [ ];
        etcFiles = missingEtc == [ ];
        directories = missingDirectories == [ ];
        stickyTmp = ((dir "/tmp").mode or null) == "1777" && ((dir "/var/tmp").mode or null) == "1777";
        vscodeHomeOwner = ((dir "/home/vscode").owner or null) == "vscode:vscode";
        runtimeDirMode = ((dir "/run/user/1000").mode or null) == "0700";
        runtimeDirOwner = ((dir "/run/user/1000").owner or null) == "vscode:vscode";
        varRunSymlink = symlinkTarget "/var/run" == "/run";
        nixDatabaseLeftToInitializer = nixDatabaseDirsPresent == [ ];
        vscodeMachineSettingsMatchProfiles = (machineSettings.settings or { }) == image.profiles.settings;
        projectionTargetsEndWithExtensions = lib.all (
          target: lib.hasSuffix projectionSuffix target
        ) projectionTargets;
        machineSettingsPaths =
          lib.sort lib.lessThan (lib.unique machineSettingPaths) == expectedMachineSettings;
        machineSettingsPermissions = invalidMachineSettingEntries == [ ];
      };
    in
    {
      inherit name checks;
      details = {
        inherit
          missingEtc
          missingShellFiles
          missingDirectories
          nixDatabaseDirsPresent
          invalidMachineSettingEntries
          ;
      };
    }
  ) images;
  allValid = lib.all (entry: lib.all (value: value) (builtins.attrValues entry.checks)) perImage;
in
{
  contracts-reports-filesystem = contractLib.mkAssertedJsonCheck "contracts-reports-filesystem" [
    allValid
  ] { images = perImage; };
}
