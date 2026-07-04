{ pkgs, lib }:
{
  config,
  compiledEnvironment ? {
    etc = [ ];
  },
  compiledShell ? {
    profileText = "";
    bashrcText = "";
    bashBashrcText = "";
    commandNotFoundHook = "";
    generatedFiles = [ ];
  },
  compiledFonts ? {
    root = null;
  },
  compiledProfiles ? {
    settings = { };
  },
}:
let
  user = config.devcontainer.user;
  osRelease = config.devcontainer.filesystem.osRelease;
  directories = config.devcontainer.filesystem.directories;
  modeChars = [
    "0"
    "1"
    "2"
    "3"
    "4"
    "5"
    "6"
    "7"
  ];
  validMode =
    mode:
    builtins.isString mode
    && (builtins.stringLength mode == 3 || builtins.stringLength mode == 4)
    && lib.all (char: builtins.elem char modeChars) (lib.stringToCharacters mode);
  validAbsolutePath =
    path:
    let
      relative = lib.removePrefix "/" path;
      segments = lib.splitString "/" relative;
    in
    lib.hasPrefix "/" path
    && relative != ""
    && !(lib.hasSuffix "/" path)
    && !(builtins.elem "" segments)
    && !(builtins.elem "." segments)
    && !(builtins.elem ".." segments);
  directoryEntries = lib.mapAttrsToList (path: spec: {
    inherit path;
    inherit (spec) mode uid gid;
    invalidPath = !(validAbsolutePath path);
    invalidMode = !(validMode spec.mode);
    invalidOwner = spec.uid < 0 || spec.gid < 0;
  }) directories;
  invalidDirectoryPaths = map (entry: entry.path) (
    builtins.filter (entry: entry.invalidPath) directoryEntries
  );
  invalidDirectoryModes = map (entry: entry.path) (
    builtins.filter (entry: entry.invalidMode) directoryEntries
  );
  invalidDirectoryOwners = map (entry: entry.path) (
    builtins.filter (entry: entry.invalidOwner) directoryEntries
  );
  validatedDirectories =
    if invalidDirectoryPaths != [ ] then
      builtins.throw (
        "devcontainer.filesystem.directories paths must be absolute normalized paths; invalid paths: "
        + lib.concatStringsSep ", " invalidDirectoryPaths
      )
    else if invalidDirectoryModes != [ ] then
      builtins.throw (
        "devcontainer.filesystem.directories must use octal modes with 3 or 4 digits; invalid paths: "
        + lib.concatStringsSep ", " invalidDirectoryModes
      )
    else if invalidDirectoryOwners != [ ] then
      builtins.throw (
        "devcontainer.filesystem.directories must use non-negative uid and gid values; invalid paths: "
        + lib.concatStringsSep ", " invalidDirectoryOwners
      )
    else
      directories;
  vscodeProjectionSuffix = "/extensions";
  vscodeProjectionSuffixLength = builtins.stringLength vscodeProjectionSuffix;
  vscodeServerRoots = lib.unique (
    map
      (
        target: builtins.substring 0 ((builtins.stringLength target) - vscodeProjectionSuffixLength) target
      )
      (
        builtins.filter (
          target: lib.hasSuffix vscodeProjectionSuffix target
        ) config.devcontainer.vscode.preinstall.projection.targets
      )
  );
  vscodeSettingsText = builtins.toJSON compiledProfiles.settings;
  vscodeMachineSettingsPaths = map (
    root:
    let
      dataDir = "${root}/data";
      machineDir = "${dataDir}/Machine";
    in
    {
      inherit root dataDir machineDir;
      settingsPath = "${machineDir}/settings.json";
      rootMode = "1777";
      dataMode = "1777";
      machineMode = "1777";
      settingsMode = "0444";
      uid = 0;
      gid = 0;
      owner = "root:root";
    }
  ) vscodeServerRoots;
  dirCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (path: spec: ''
      mkdir -p "$out${path}"
      chmod ${spec.mode} "$out${path}"
    '') validatedDirectories
  );
  etcCommands = lib.concatStringsSep "\n" (
    map (
      entry:
      let
        parent = builtins.dirOf entry.path;
        source = lib.escapeShellArg entry.source;
      in
      if entry.source != null then
        ''
          rm -rf "$out${entry.path}"
          mkdir -p "$out${parent}"
          if [ -d ${source} ]; then
            mkdir -p "$out${entry.path}"
            cp -a ${source}/. "$out${entry.path}/"
          else
            cp -L ${source} "$out${entry.path}"
          fi
          chmod ${entry.mode} "$out${entry.path}"
        ''
      else
        ''
          mkdir -p "$out${parent}"
          printf '%s' ${lib.escapeShellArg entry.text} >"$out${entry.path}"
          chmod ${entry.mode} "$out${entry.path}"
        ''
    ) compiledEnvironment.etc
  );
  vscodeMachineSettingsCommands = lib.concatStringsSep "\n" (
    map (entry: ''
      mkdir -p "$out${entry.root}" "$out${entry.dataDir}" "$out${entry.machineDir}"
      chmod ${entry.rootMode} "$out${entry.root}"
      chmod ${entry.dataMode} "$out${entry.dataDir}"
      printf '%s' ${lib.escapeShellArg vscodeSettingsText} >"$out${entry.settingsPath}"
      chmod ${entry.machineMode} "$out${entry.machineDir}"
      chmod ${entry.settingsMode} "$out${entry.settingsPath}"
    '') vscodeMachineSettingsPaths
  );
  passwdText = lib.concatStringsSep "\n" [
    "root:x:0:0:root:/root:/bin/bash"
    "${user.name}:x:${toString user.uid}:${toString user.gid}:${user.name}:${user.home}:${user.shell}"
    ""
  ];
  nixpkgsConfigPath = "/etc/nixpkgs/config.nix";
  nixpkgsConfigText = ''
    {
      allowUnfree = true;
      android_sdk.accept_license = true;
      oraclejdk.accept_license = true;
      allowUnsupportedSystem = true;
    }
  '';
  userBashrcPath = "${user.home}/.bashrc";
  userBashrcText = ''
    if [ -r /etc/bashrc ]; then
      . /etc/bashrc
    fi
  '';
  groupText = lib.concatStringsSep "\n" [
    "root:x:0:"
    "${user.group}:x:${toString user.gid}:${user.name}"
    ""
  ];
  osReleaseText = lib.concatStringsSep "\n" [
    ''NAME="${osRelease.name}"''
    "ID=${osRelease.id}"
    ''VERSION_ID="${osRelease.versionId}"''
    ''PRETTY_NAME="${osRelease.prettyName}"''
    ""
  ];
  symlinks = [
    {
      path = "/var/run";
      target = "/run";
    }
  ];
  root = pkgs.runCommand "${config.devcontainer.image.name}-filesystem" { } ''
    mkdir -p "$out/etc/profile.d" "$out/etc/nixpkgs"
    mkdir -p "$out/root"
    ${dirCommands}
    ln -sfn /run "$out/var/run"

    printf '%s' ${lib.escapeShellArg passwdText} >"$out/etc/passwd"
    printf '%s' ${lib.escapeShellArg groupText} >"$out/etc/group"
    printf '%s' ${lib.escapeShellArg osReleaseText} >"$out/etc/os-release"
    printf '%s' ${lib.escapeShellArg compiledShell.profileText} >"$out/etc/profile"
    printf '%s' ${lib.escapeShellArg compiledShell.bashrcText} >"$out/etc/bashrc"
    printf '%s' ${lib.escapeShellArg compiledShell.bashBashrcText} >"$out/etc/bash.bashrc"
    printf '%s' ${lib.escapeShellArg nixpkgsConfigText} >"$out${nixpkgsConfigPath}"
    printf '%s' ${lib.escapeShellArg userBashrcText} >"$out${userBashrcPath}"
    ${etcCommands}
    ${vscodeMachineSettingsCommands}
    ${lib.optionalString (compiledFonts.root != null) ''
      cp -a ${compiledFonts.root}/. "$out/"
    ''}

    chmod 0644 "$out/etc/passwd" "$out/etc/group" "$out/etc/os-release" "$out/etc/profile" "$out/etc/bashrc" "$out/etc/bash.bashrc" "$out${nixpkgsConfigPath}" "$out${userBashrcPath}"
  '';
  userPermName = spec: if spec.uid == 0 then "root" else user.name;
  groupPermName = spec: if spec.gid == 0 then "root" else user.group;
  mkPerm = path: spec: {
    inherit (spec) mode uid gid;
    path = root;
    regex = "^${root}${path}(/.*)?$";
    uname = userPermName spec;
    gname = groupPermName spec;
  };
  directoryPerms = lib.mapAttrsToList mkPerm validatedDirectories;
  filePerms = [
    {
      path = root;
      regex = "^${root}/etc/(passwd|group|os-release|profile|bashrc|bash\\.bashrc|nixpkgs/config\\.nix)$";
      mode = "0644";
      uid = 0;
      gid = 0;
      uname = "root";
      gname = "root";
    }
    {
      path = root;
      regex = "^${root}${userBashrcPath}$";
      mode = "0644";
      uid = user.uid;
      gid = user.gid;
      uname = user.name;
      gname = user.group;
    }
  ]
  ++ map (entry: {
    path = root;
    regex = "^${root}${entry.path}$";
    inherit (entry) mode uid gid;
    uname = userPermName entry;
    gname = groupPermName entry;
  }) compiledEnvironment.etc;
  vscodeMachineSettingsPerms = lib.concatMap (entry: [
    {
      path = root;
      regex = "^${root}${entry.root}$";
      mode = entry.rootMode;
      uid = entry.uid;
      gid = entry.gid;
      uname = "root";
      gname = "root";
    }
    {
      path = root;
      regex = "^${root}${entry.dataDir}$";
      mode = entry.dataMode;
      uid = entry.uid;
      gid = entry.gid;
      uname = "root";
      gname = "root";
    }
    {
      path = root;
      regex = "^${root}${entry.machineDir}$";
      mode = entry.machineMode;
      uid = entry.uid;
      gid = entry.gid;
      uname = "root";
      gname = "root";
    }
    {
      path = root;
      regex = "^${root}${entry.settingsPath}$";
      mode = entry.settingsMode;
      uid = entry.uid;
      gid = entry.gid;
      uname = "root";
      gname = "root";
    }
  ]) vscodeMachineSettingsPaths;
in
{
  inherit root;
  passwd = passwdText;
  group = groupText;
  osRelease = osReleaseText;
  nixpkgsConfig = {
    path = nixpkgsConfigPath;
    text = nixpkgsConfigText;
  };
  commandNotFoundHook = compiledShell.commandNotFoundHook;
  shellFiles = compiledShell.generatedFiles ++ [ userBashrcPath ];
  etcFiles = map (entry: {
    inherit (entry)
      name
      target
      path
      mode
      uid
      gid
      sourcePath
      ;
    hasText = entry.text != null;
  }) compiledEnvironment.etc;
  vscodeMachineSettings = {
    settings = compiledProfiles.settings;
    paths = vscodeMachineSettingsPaths;
  };
  perms = directoryPerms ++ filePerms ++ vscodeMachineSettingsPerms;
  directories = lib.mapAttrsToList (path: spec: {
    inherit path;
    inherit (spec) mode uid gid;
    owner =
      if spec.uid == user.uid && spec.gid == user.gid then "${user.name}:${user.group}" else "root:root";
  }) validatedDirectories;
  inherit symlinks;
}
