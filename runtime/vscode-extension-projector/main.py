#!/usr/bin/env python3
import json
import os
import re
import shutil
import sys
from pathlib import Path


USAGE = "vscode-extension-projector activate --index <path>\n"
PREFIX_SECRET_PATTERNS = [
    re.compile(
        r"([A-Za-z0-9_.:/-]*(?:TOKEN|PASSWORD|PASSWD|PWD|SECRET|KEY|API[_-]?KEY|ACCESS[_-]?KEY|PRIVATE[_-]?KEY|AUTH[_-]?TOKEN|CREDENTIAL|CLIENT[_-]?SECRET)[A-Za-z0-9_.:/-]*=)[^\s]+",
        re.IGNORECASE,
    ),
    re.compile(r"((?:Authorization|Proxy-Authorization):\s*)[\x21-\x7e]+", re.IGNORECASE),
    re.compile(r"(\bsig=)[^&\s;]+", re.IGNORECASE),
    re.compile(r"(\bSharedAccessSignature=)[^\s;]+", re.IGNORECASE),
]
VALUE_SECRET_PATTERNS = [
    re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bnpm_[A-Za-z0-9]{30,}\b"),
    re.compile(r"\b(?:A3T[A-Z0-9]|AKIA|AGPA|AIDA|AROA|ASIA)[A-Z0-9]{16}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    re.compile(r"\bya29\.[0-9A-Za-z_-]+\b"),
]


def usage(file=sys.stdout):
    print(USAGE, end="", file=file)


def fail(message: str) -> None:
    print(redact(message), file=sys.stderr)
    raise SystemExit(1)


def redact(text: str) -> str:
    for pattern in PREFIX_SECRET_PATTERNS:
        text = pattern.sub(lambda match: f"{match.group(1)}[REDACTED]", text)
    for pattern in VALUE_SECRET_PATTERNS:
        text = pattern.sub("[REDACTED]", text)
    return text


def log(message: str, *, error: bool = False) -> None:
    print(redact(message), file=sys.stderr if error else sys.stdout)


def read_index(index_file: Path) -> dict:
    if not index_file.is_file():
        fail(f"index file not found: {index_file}")
    with index_file.open("r", encoding="utf-8") as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as exc:
            fail(f"invalid index JSON: {exc}")
    targets = data.get("projectionTargets")
    extensions = data.get("extensions")
    if not isinstance(targets, list) or not all(isinstance(target, str) and target for target in targets):
        fail("index projectionTargets must be a non-empty string array")
    if not isinstance(extensions, list):
        fail("index extensions must be an array")
    return data


def safe_dest_name(source_path: Path) -> str:
    name = source_path.name
    if name in {"", ".", ".."} or "/" in name or "\\" in name:
        fail(f"unsafe extension destination name: {name!r}")
    return name


def assert_within_target(target: Path, target_path: Path) -> None:
    target_abs = os.path.abspath(os.fspath(target))
    path_abs = os.path.abspath(os.fspath(target_path))
    try:
        common = os.path.commonpath([target_abs, path_abs])
    except ValueError:
        fail(f"projection target path escapes target: {target_path}")
    if common != target_abs:
        fail(f"projection target path escapes target: {target_path}")


def remove_existing(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def copy_or_link(source_path: Path, target_path: Path, projection: str) -> None:
    target_path.parent.mkdir(parents=True, exist_ok=True)
    remove_existing(target_path)
    if projection in {"copy", "copy-if-needed", "copy-if-needed-with-fhs"}:
        if source_path.is_dir():
            shutil.copytree(source_path, target_path, symlinks=True)
        else:
            shutil.copy2(source_path, target_path)
    else:
        os.symlink(source_path, target_path)


def activate(index_file: Path) -> int:
    data = read_index(index_file)
    targets = [Path(target) for target in data["projectionTargets"]]
    for target in targets:
        target.mkdir(parents=True, exist_ok=True)

    for extension in data["extensions"]:
        if not isinstance(extension, dict):
            fail("index extension entries must be objects")
        extension_id = extension.get("id")
        source = extension.get("path")
        projection = extension.get("projection")
        required = extension.get("required")
        if not isinstance(extension_id, str) or not extension_id:
            fail("extension entry must include an id")
        if not isinstance(source, str) or not source:
            fail(f"extension {extension_id} must include a path")
        if not isinstance(projection, str) or not projection:
            fail(f"extension {extension_id} must include a projection")
        if not isinstance(required, bool):
            fail(f"extension {extension_id} must include a boolean required value")

        source_path = Path(source)
        dest_name = safe_dest_name(source_path)
        if not source_path.exists():
            message = f"missing extension source for {extension_id}: {source_path}"
            if required:
                fail(message)
            log(message, error=True)
            continue

        for target in targets:
            target_path = target / dest_name
            assert_within_target(target, target_path)
            log(f"project {extension_id} -> {target_path}")
            copy_or_link(source_path, target_path, projection)
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[0] != "activate" or argv[1] != "--index":
        usage(sys.stderr)
        return 1
    return activate(Path(argv[2]))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
