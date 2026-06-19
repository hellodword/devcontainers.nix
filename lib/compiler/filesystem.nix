{ pkgs, lib }:
{ config, compiledFhsRuntime }:
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
  passwdText = lib.concatStringsSep "\n" [
    "root:x:0:0:root:/root:/bin/bash"
    "${user.name}:x:${toString user.uid}:${toString user.gid}:${user.name}:${user.home}:${user.shell}"
    ""
  ];
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
  commandNotFoundHook = lib.concatStringsSep "\n" [
    "command_not_found_handle() {"
    ''local command="$1"''
    "  shift || true"
    "  if command -v nix-locate >/dev/null 2>&1; then"
    ''printf '%s: command not found\n' "$command" >&2''
    ''nix-locate --minimal --whole-name --at-root "/bin/$command" 2>/dev/null | head -n 20 >&2 || true''
    "  else"
    ''printf '%s: command not found\n' "$command" >&2''
    "  fi"
    "  return 127"
    "}"
    ""
  ];
  root = pkgs.runCommand "${config.devcontainer.image.name}-filesystem" { } ''
    mkdir -p "$out/etc/profile.d"
    mkdir -p "$out/root"
    ${dirCommands}

    printf '%s' ${lib.escapeShellArg passwdText} >"$out/etc/passwd"
    printf '%s' ${lib.escapeShellArg groupText} >"$out/etc/group"
    printf '%s' ${lib.escapeShellArg osReleaseText} >"$out/etc/os-release"
    printf '%s' ${lib.escapeShellArg commandNotFoundHook} >"$out/etc/profile.d/command-not-found.sh"

    chmod 0644 "$out/etc/passwd" "$out/etc/group" "$out/etc/os-release" "$out/etc/profile.d/command-not-found.sh"
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
      regex = "^${root}/etc/(passwd|group|os-release)$";
      mode = "0644";
      uid = 0;
      gid = 0;
      uname = "root";
      gname = "root";
    }
    {
      path = root;
      regex = "^${root}/etc/profile.d/command-not-found.sh$";
      mode = "0644";
      uid = 0;
      gid = 0;
      uname = "root";
      gname = "root";
    }
  ];
in
{
  inherit root;
  passwd = passwdText;
  group = groupText;
  osRelease = osReleaseText;
  commandNotFoundHook = commandNotFoundHook;
  perms = directoryPerms ++ filePerms;
  directories = lib.mapAttrsToList (path: spec: {
    inherit path;
    inherit (spec) mode uid gid;
    owner =
      if spec.uid == user.uid && spec.gid == user.gid then "${user.name}:${user.group}" else "root:root";
  }) directories;
  fhsOsRelease = compiledFhsRuntime.osReleaseText;
}
