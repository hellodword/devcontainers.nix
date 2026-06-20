{ pkgs, lib }:
{
  config,
  compiledEnvironment ? {
    etc = [ ];
  },
  compiledFhsRuntime,
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
}:
let
  user = config.devcontainer.user;
  osRelease = config.devcontainer.filesystem.osRelease;
  directories = config.devcontainer.filesystem.directories;
  dirCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (path: spec: ''
      mkdir -p "$out${path}"
      chmod ${spec.mode} "$out${path}"
    '') directories
  );
  etcCommands = lib.concatStringsSep "\n" (
    map (
      entry:
      let
        parent = builtins.dirOf entry.path;
      in
      if entry.source != null then
        ''
          rm -rf "$out${entry.path}"
          mkdir -p "$out${parent}"
          if [ -d ${lib.escapeShellArg entry.sourcePath} ]; then
            mkdir -p "$out${entry.path}"
            cp -a ${lib.escapeShellArg entry.sourcePath}/. "$out${entry.path}/"
          else
            cp -L ${lib.escapeShellArg entry.sourcePath} "$out${entry.path}"
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
  directoryPerms = lib.mapAttrsToList mkPerm directories;
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
  perms = directoryPerms ++ filePerms;
  directories = lib.mapAttrsToList (path: spec: {
    inherit path;
    inherit (spec) mode uid gid;
    owner =
      if spec.uid == user.uid && spec.gid == user.gid then "${user.name}:${user.group}" else "root:root";
  }) directories;
  inherit symlinks;
  fhsOsRelease = compiledFhsRuntime.osReleaseText;
}
