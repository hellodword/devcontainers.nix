import json
import pathlib
import sys
from collections.abc import Iterable
from typing import Any


def fail(prefix: str, message: str) -> None:
    print(f"{prefix} failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: pathlib.Path, prefix: str) -> Any:
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        fail(prefix, f"required JSON file not found: {path}")
    except json.JSONDecodeError as exc:
        fail(prefix, f"invalid JSON in {path}: {exc}")


def walk_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, child in value.items():
            yield str(key)
            yield from walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_strings(child)


def parse_env_entries(entries: list[Any], prefix: str) -> dict[str, str]:
    if not isinstance(entries, list):
        fail(prefix, "image Env must be a list")
    parsed: dict[str, str] = {}
    duplicates: list[str] = []
    invalid: list[str] = []
    for entry in entries:
        if not isinstance(entry, str) or "=" not in entry:
            invalid.append(str(entry))
            continue
        name, value = entry.split("=", 1)
        if not name:
            invalid.append(entry)
            continue
        if name in parsed:
            duplicates.append(name)
        parsed[name] = value
    if invalid:
        fail(prefix, f"image Env contains invalid entries: {invalid}")
    if duplicates:
        fail(prefix, f"image Env contains duplicate names: {sorted(set(duplicates))}")
    return parsed
