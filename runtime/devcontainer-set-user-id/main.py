#!/usr/bin/env python3
import argparse
import os
import shutil
import stat
import sys
from dataclasses import dataclass
from pathlib import Path


USER_NAME = "vscode"
GROUP_NAME = "vscode"
MAX_ID = 2_147_483_647


class UsageError(Exception):
    pass


class ApplyError(Exception):
    pass


@dataclass(frozen=True)
class Identity:
    old_uid: int
    old_gid: int
    uid: int
    gid: int


def parse_numeric_id(name: str, value: str) -> int:
    if not value or not value.isdecimal():
        raise UsageError(f"{name} must be a decimal integer")
    parsed = int(value, 10)
    if parsed < 1 or parsed > MAX_ID:
        raise UsageError(f"{name} must be between 1 and {MAX_ID}")
    return parsed


def parser() -> argparse.ArgumentParser:
    arg_parser = argparse.ArgumentParser(
        prog="devcontainer-set-user-id",
        description="Set the fixed vscode account to a numeric UID/GID.",
    )
    arg_parser.add_argument("--uid", required=True, help="numeric UID for the vscode user")
    arg_parser.add_argument("--gid", required=True, help="numeric GID for the vscode group")
    return arg_parser


def parse_args(argv: list[str]) -> tuple[int, int]:
    args = parser().parse_args(argv)
    try:
        return parse_numeric_id("--uid", args.uid), parse_numeric_id("--gid", args.gid)
    except UsageError as exc:
        raise UsageError(str(exc)) from exc


def read_lines(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ApplyError(f"failed to read {path}: {exc}") from exc


def write_lines(path: Path, lines: list[str]) -> None:
    try:
        original_mode = stat.S_IMODE(path.stat().st_mode)
        tmp_path = path.with_name(f".{path.name}.tmp")
        tmp_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        os.chmod(tmp_path, original_mode)
        os.replace(tmp_path, path)
    except OSError as exc:
        raise ApplyError(f"failed to write {path}: {exc}") from exc


def split_entry(path: Path, line: str, minimum_fields: int) -> list[str]:
    fields = line.split(":")
    if len(fields) < minimum_fields:
        raise ApplyError(f"malformed entry in {path}: {line}")
    return fields


def find_passwd_entry(passwd_path: Path, lines: list[str]) -> tuple[int, list[str]]:
    for index, line in enumerate(lines):
        fields = split_entry(passwd_path, line, 7)
        if fields[0] == USER_NAME:
            return index, fields
    raise ApplyError(f"{passwd_path} does not contain {USER_NAME}")


def find_group_entry(group_path: Path, lines: list[str]) -> tuple[int, list[str]]:
    for index, line in enumerate(lines):
        fields = split_entry(group_path, line, 4)
        if fields[0] == GROUP_NAME:
            return index, fields
    raise ApplyError(f"{group_path} does not contain {GROUP_NAME}")


def reject_uid_conflict(passwd_path: Path, lines: list[str], uid: int) -> None:
    for line in lines:
        fields = split_entry(passwd_path, line, 7)
        name = fields[0]
        try:
            existing_uid = int(fields[2], 10)
        except ValueError as exc:
            raise ApplyError(f"invalid UID in {passwd_path}: {line}") from exc
        if name != USER_NAME and existing_uid == uid and existing_uid != 0:
            raise ApplyError(f"UID {uid} already belongs to user {name}")


def reject_gid_conflict(group_path: Path, lines: list[str], gid: int) -> None:
    for line in lines:
        fields = split_entry(group_path, line, 4)
        name = fields[0]
        try:
            existing_gid = int(fields[2], 10)
        except ValueError as exc:
            raise ApplyError(f"invalid GID in {group_path}: {line}") from exc
        if name != GROUP_NAME and existing_gid == gid and existing_gid != 0:
            raise ApplyError(f"GID {gid} already belongs to group {name}")


def rewrite_identity(root: Path, uid: int, gid: int) -> Identity:
    passwd_path = root / "etc/passwd"
    group_path = root / "etc/group"
    passwd_lines = read_lines(passwd_path)
    group_lines = read_lines(group_path)

    passwd_index, passwd_fields = find_passwd_entry(passwd_path, passwd_lines)
    group_index, group_fields = find_group_entry(group_path, group_lines)
    reject_uid_conflict(passwd_path, passwd_lines, uid)
    reject_gid_conflict(group_path, group_lines, gid)

    try:
        old_uid = int(passwd_fields[2], 10)
        old_gid = int(passwd_fields[3], 10)
    except ValueError as exc:
        raise ApplyError(f"invalid {USER_NAME} UID/GID in {passwd_path}") from exc

    passwd_fields[2] = str(uid)
    passwd_fields[3] = str(gid)
    passwd_lines[passwd_index] = ":".join(passwd_fields)

    group_fields[2] = str(gid)
    members = [member for member in group_fields[3].split(",") if member]
    if USER_NAME not in members:
        members.append(USER_NAME)
    group_fields[3] = ",".join(members)
    group_lines[group_index] = ":".join(group_fields)

    write_lines(passwd_path, passwd_lines)
    write_lines(group_path, group_lines)
    return Identity(old_uid=old_uid, old_gid=old_gid, uid=uid, gid=gid)


def chown_path(path: Path, uid: int, gid: int) -> None:
    if not path.exists() and not path.is_symlink():
        return
    try:
        os.chown(path, uid, gid, follow_symlinks=False)
    except OSError as exc:
        raise ApplyError(f"failed to chown {path}: {exc}") from exc


def chown_matching_path(path: Path, identity: Identity) -> None:
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return
    except OSError as exc:
        raise ApplyError(f"failed to stat {path}: {exc}") from exc

    uid = identity.uid if st.st_uid == identity.old_uid else st.st_uid
    gid = identity.gid if st.st_gid == identity.old_gid else st.st_gid
    if uid == st.st_uid and gid == st.st_gid:
        return
    try:
        os.chown(path, uid, gid, follow_symlinks=False)
    except OSError as exc:
        raise ApplyError(f"failed to chown {path}: {exc}") from exc


def chown_matching_tree(path: Path, identity: Identity) -> None:
    if not path.exists() and not path.is_symlink():
        return
    chown_matching_path(path, identity)
    if path.is_symlink() or not path.is_dir():
        return
    for current, dirs, files in os.walk(path, followlinks=False):
        current_path = Path(current)
        chown_matching_path(current_path, identity)
        for name in dirs + files:
            chown_matching_path(current_path / name, identity)


def chown_tree(path: Path, uid: int, gid: int) -> None:
    if not path.exists() and not path.is_symlink():
        return
    chown_path(path, uid, gid)
    if path.is_symlink() or not path.is_dir():
        return
    for current, dirs, files in os.walk(path, followlinks=False):
        current_path = Path(current)
        chown_path(current_path, uid, gid)
        for name in dirs + files:
            chown_path(current_path / name, uid, gid)


def remove_stale_runtime_dir(path: Path, identity: Identity) -> None:
    if not path.exists() and not path.is_symlink():
        return
    try:
        st = os.lstat(path)
    except OSError as exc:
        raise ApplyError(f"failed to stat {path}: {exc}") from exc
    if path.is_symlink() or not stat.S_ISDIR(st.st_mode):
        return
    if st.st_uid != identity.old_uid or st.st_gid != identity.old_gid:
        return
    try:
        shutil.rmtree(path)
    except OSError as exc:
        raise ApplyError(f"failed to remove stale runtime dir {path}: {exc}") from exc


def ensure_runtime_dir(root: Path, identity: Identity) -> None:
    runtime_parent = root / "run/user"
    runtime_dir = runtime_parent / str(identity.uid)
    stale_dir = runtime_parent / str(identity.old_uid)
    try:
        runtime_parent.mkdir(parents=True, exist_ok=True)
        runtime_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(runtime_dir, 0o700)
    except OSError as exc:
        raise ApplyError(f"failed to create {runtime_dir}: {exc}") from exc
    chown_path(runtime_dir, identity.uid, identity.gid)
    if identity.old_uid != identity.uid:
        remove_stale_runtime_dir(stale_dir, identity)


def apply_ownership(root: Path, identity: Identity) -> None:
    chown_matching_tree(root / "home/vscode", identity)
    ensure_runtime_dir(root, identity)
    for path in [
        root / "nix",
        root / "nix/store",
        root / "nix/var",
        root / "nix/var/log",
    ]:
        chown_path(path, identity.uid, identity.gid)
    for path in [
        root / "nix/var/nix",
        root / "nix/var/log/nix",
    ]:
        chown_tree(path, identity.uid, identity.gid)


def set_user_id(root: Path, uid: int, gid: int) -> None:
    identity = rewrite_identity(root, uid, gid)
    apply_ownership(root, identity)


def main(argv: list[str]) -> int:
    try:
        uid, gid = parse_args(argv)
    except UsageError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    try:
        set_user_id(Path("/"), uid, gid)
    except ApplyError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
