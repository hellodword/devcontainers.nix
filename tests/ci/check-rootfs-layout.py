#!/usr/bin/env python3
import argparse
import json
import os
import pathlib
import sys


def fail(message: str):
    print(f"rootfs-layout-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: pathlib.Path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        fail(f"required JSON file not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def root_path(rootfs: pathlib.Path, absolute_path: str) -> pathlib.Path:
    if not absolute_path.startswith("/"):
        fail(f"path must be absolute: {absolute_path}")
    return rootfs / absolute_path.lstrip("/")


def require_exists(rootfs: pathlib.Path, absolute_path: str):
    path = root_path(rootfs, absolute_path)
    if not path.exists():
        fail(f"rootfs missing {absolute_path}")


def require_absent(rootfs: pathlib.Path, absolute_path: str):
    path = root_path(rootfs, absolute_path)
    if path.exists() or path.is_symlink():
        fail(f"rootfs must not contain {absolute_path}")


def require_symlink(rootfs: pathlib.Path, absolute_path: str, target: str):
    path = root_path(rootfs, absolute_path)
    if not path.is_symlink():
        fail(f"rootfs {absolute_path} must be a symlink")
    actual = os.readlink(path)
    if actual != target:
        fail(f"rootfs {absolute_path} must point to {target}, got {actual}")


def require_declared_commands(rootfs: pathlib.Path, reports_dir: pathlib.Path):
    profile_report = read_json(reports_dir / "profile-report.json")
    provided_commands = profile_report.get("provides", {}).get("commands") or []
    search_dirs = [
        "/usr/local/bin",
        "/usr/local/sbin",
        "/usr/bin",
        "/usr/sbin",
        "/bin",
        "/sbin",
    ]
    missing = []
    invalid = []

    for command in sorted(set(provided_commands)):
        if not command or "/" in command:
            invalid.append(command)
            continue
        if not any(root_path(rootfs, f"{directory}/{command}").exists() for directory in search_dirs):
            missing.append(command)

    if invalid:
        fail(f"profile-report.json declares invalid command names: {', '.join(invalid)}")
    if missing:
        fail(f"profile-report.json declares commands missing from rootfs PATH: {', '.join(missing)}")


def require_vscode_machine_settings(rootfs: pathlib.Path, reports_dir: pathlib.Path, projection_targets):
    profile_report = read_json(reports_dir / "profile-report.json")
    filesystem_report = read_json(reports_dir / "filesystem-report.json")
    profile_settings = (profile_report.get("vscode") or {}).get("settings") or {}
    machine_settings = filesystem_report.get("vscodeMachineSettings") or {}

    if machine_settings.get("settings") != profile_settings:
        fail("filesystem report VS Code machine settings must match profile report")

    projection_suffix = "/extensions"
    expected_paths = set()
    for target in projection_targets:
        if not isinstance(target, str) or not target.endswith(projection_suffix):
            fail(f"VS Code extension projection target must end with {projection_suffix}: {target}")
        expected_paths.add(f"{target[:-len(projection_suffix)]}/data/Machine/settings.json")
    entries = machine_settings.get("paths") or []
    seen_paths = {entry.get("settingsPath") for entry in entries}
    if seen_paths != expected_paths:
        fail("filesystem report missing VS Code machine settings paths")

    for entry in entries:
        if entry.get("owner") != "root:root":
            fail("VS Code machine settings must be owned by root:root")
        if entry.get("rootMode") != "1777" or entry.get("dataMode") != "1777":
            fail("VS Code server roots and data dirs must be sticky writable")
        if entry.get("machineMode") != "1777":
            fail("VS Code Machine dir must be sticky writable")
        if entry.get("settingsMode") != "0444":
            fail("VS Code Machine settings file must be read-only")
        require_exists(rootfs, entry.get("root"))
        require_exists(rootfs, entry.get("dataDir"))
        require_exists(rootfs, entry.get("machineDir"))
        settings_path = entry.get("settingsPath")
        require_exists(rootfs, settings_path)
        if read_json(root_path(rootfs, settings_path)) != profile_settings:
            fail(f"VS Code machine settings content mismatch: {settings_path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("rootfs", type=pathlib.Path)
    parser.add_argument("reports_dir", type=pathlib.Path)
    parser.add_argument("image_name")
    parser.add_argument("--require", action="append", default=[])
    args = parser.parse_args()

    if not args.rootfs.is_dir():
        fail(f"rootfs is not a directory: {args.rootfs}")

    for directory in [
        "/usr/bin",
        "/usr/sbin",
        "/usr/lib",
        "/usr/lib64",
        "/usr/libexec",
        "/usr/include",
        "/usr/share",
        "/usr/local/bin",
        "/usr/local/etc",
        "/usr/local/include",
        "/usr/local/lib",
        "/usr/local/lib64",
        "/usr/local/sbin",
        "/usr/local/share",
        "/usr/local/src",
        "/etc/xdg",
        "/var/cache",
        "/var/lib",
        "/var/log",
        "/var/tmp",
        "/run/user/1000",
    ]:
        require_exists(args.rootfs, directory)

    for absolute_path, target in {
        "/bin": "usr/bin",
        "/sbin": "usr/sbin",
        "/lib": "usr/lib",
        "/lib64": "usr/lib64",
        "/libexec": "usr/libexec",
        "/include": "usr/include",
        "/share": "usr/share",
        "/var/run": "/run",
    }.items():
        require_symlink(args.rootfs, absolute_path, target)

    for absolute_path in [
        "/usr/bin/devcontainer-entrypoint",
        "/usr/bin/env",
        "/bin/bash",
        "/bin/sh",
        "/usr/share/devcontainer/tasks.json",
        "/usr/share/devcontainer/vscode/extensions-index.json",
    ]:
        require_exists(args.rootfs, absolute_path)

    for absolute_path in args.require:
        require_exists(args.rootfs, absolute_path)

    for absolute_path in [
        "/usr/local/bin/devcontainer-entrypoint",
        "/usr/local/bin/node",
        "/usr/local/bin/python",
        "/usr/local/bin/go",
        "/usr/local/bin/rust-analyzer",
        "/usr/local/bin/protols",
        "/usr/local/bin/shellcheck",
        "/usr/local/share/typescript",
        "/usr/local/go",
        "/usr/sbin/ldconfig",
        "/sbin/ldconfig",
    ]:
        require_absent(args.rootfs, absolute_path)

    filesystem_report = read_json(args.reports_dir / "filesystem-report.json")
    directory_map = {entry.get("path"): entry for entry in filesystem_report.get("directories", [])}
    runtime_report = directory_map.get("/run/user/1000") or {}
    if runtime_report.get("owner") != "vscode:vscode":
        fail("filesystem report must declare /run/user/1000 owner as vscode:vscode")
    if runtime_report.get("mode") != "0700":
        fail("filesystem report must declare /run/user/1000 mode as 0700")

    extensions_index = read_json(root_path(args.rootfs, "/usr/share/devcontainer/vscode/extensions-index.json"))
    projection_targets = set(extensions_index.get("projectionTargets") or [])
    require_declared_commands(args.rootfs, args.reports_dir)
    require_vscode_machine_settings(args.rootfs, args.reports_dir, projection_targets)

    expected_projection_targets = {
        "/home/vscode/.vscode-server/extensions",
        "/home/vscode/.vscode-server-insiders/extensions",
        "/home/vscode/.vscode-remote/extensions",
    }
    missing_projection_targets = sorted(expected_projection_targets - projection_targets)
    if missing_projection_targets:
        fail(f"extensions index missing projection targets: {missing_projection_targets}")

    print(f"rootfs-layout-check ok: {args.image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
