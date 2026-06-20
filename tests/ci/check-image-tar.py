#!/usr/bin/env python3
import json
import pathlib
import re
import sys
from decimal import Decimal, InvalidOperation, ROUND_CEILING


SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)
SIZE_RE = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*([kmgt]?i?b?|b)?\s*$", re.IGNORECASE)
SIZE_UNITS = {
    "": 1,
    "b": 1,
    "k": 1000,
    "kb": 1000,
    "ki": 1024,
    "kib": 1024,
    "m": 1000**2,
    "mb": 1000**2,
    "mi": 1024**2,
    "mib": 1024**2,
    "g": 1000**3,
    "gb": 1000**3,
    "gi": 1024**3,
    "gib": 1024**3,
    "t": 1000**4,
    "tb": 1000**4,
    "ti": 1024**4,
    "tib": 1024**4,
}


def fail(message: str):
    print(f"image-artifact-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: pathlib.Path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        fail(f"required JSON file not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def parse_size_bytes(value) -> int:
    if isinstance(value, bool):
        fail("layer budget maxLayerSize must be a size string or positive integer")
    if isinstance(value, int):
        if value <= 0:
            fail("layer budget maxLayerSize must be positive")
        return value
    if not isinstance(value, str):
        fail("layer budget maxLayerSize must be a size string or positive integer")

    match = SIZE_RE.match(value)
    if not match:
        fail(f"layer budget maxLayerSize has unsupported format: {value}")

    try:
        number = Decimal(match.group(1))
    except InvalidOperation:
        fail(f"layer budget maxLayerSize has unsupported number: {value}")

    if number <= 0:
        fail("layer budget maxLayerSize must be positive")

    unit = (match.group(2) or "").lower()
    multiplier = SIZE_UNITS.get(unit)
    if multiplier is None:
        fail(f"layer budget maxLayerSize has unsupported unit: {value}")

    return int((number * multiplier).to_integral_value(rounding=ROUND_CEILING))


def format_bytes(size: int) -> str:
    gib = size / 1024**3
    if gib >= 1:
        return f"{gib:.2f} GiB"
    mib = size / 1024**2
    if mib >= 1:
        return f"{mib:.2f} MiB"
    return f"{size} B"


def layer_label(index: int, layer: dict) -> str:
    history = layer.get("History") if isinstance(layer.get("History"), dict) else {}
    created_by = history.get("created_by")
    digest = layer.get("digest")
    detail = created_by or digest
    if detail:
        return f"layer {index} ({detail})"
    return f"layer {index}"


def walk_strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, child in value.items():
            yield str(key)
            yield from walk_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_strings(child)


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: tests/ci/check-image-tar.py <nix2container-image-json> <reports-dir> <image-name>",
            file=sys.stderr,
        )
        return 1

    image_path = pathlib.Path(sys.argv[1])
    reports_dir = pathlib.Path(sys.argv[2])
    image_name = sys.argv[3]

    if not image_path.is_file():
        fail(f"image artifact is not a file: {image_path}")
    if image_path.stat().st_size == 0:
        fail("image artifact is empty")

    image_json = read_json(image_path)
    layer_plan = read_json(reports_dir / "layer-plan.json")
    max_layer_size = parse_size_bytes(layer_plan.get("budget", {}).get("maxLayerSize"))

    if image_json.get("version") != 1:
        fail("image artifact must use nix2container JSON version 1")
    if image_json.get("arch") != "amd64":
        fail("image artifact must target amd64")

    image_config = image_json.get("image-config")
    if not isinstance(image_config, dict):
        fail("image artifact must contain an image-config object")
    if image_config.get("User") != "vscode":
        fail("image artifact must default to the vscode user")
    if image_config.get("WorkingDir") != "/workspaces":
        fail("image artifact must use /workspaces as the working directory")
    if image_config.get("Entrypoint") != ["/usr/bin/devcontainer-entrypoint"]:
        fail("image artifact entrypoint mismatch")

    env = image_config.get("Env")
    if not isinstance(env, list) or "HOME=/home/vscode" not in env:
        fail("image artifact must set HOME for the vscode user")
    for required_env in [
        "XDG_CONFIG_HOME=/home/vscode/.config",
        "XDG_CACHE_HOME=/home/vscode/.cache",
        "XDG_DATA_HOME=/home/vscode/.local/share",
        "XDG_STATE_HOME=/home/vscode/.local/state",
        "XDG_RUNTIME_DIR=/run/user/1000",
        "LANG=en_US.UTF-8",
        "LANGUAGE=en_US:en",
        "XDG_CONFIG_DIRS=/etc/xdg",
        "XDG_DATA_DIRS=/usr/local/share:/usr/share",
        "NIXPKGS_CONFIG=/etc/nixpkgs/config.nix",
        "NIXPKGS_ALLOW_UNFREE=1",
        "NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1",
        "NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1",
        "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
        "CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt",
        "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt",
        "TZDIR=/etc/zoneinfo",
    ]:
        if required_env not in env:
            fail(f"image artifact must set expanded {required_env.split('=', 1)[0]}")
    devpkg_ref_entries = [entry for entry in env if entry.startswith("DEVPKG_NIXPKGS_REF=")]
    if len(devpkg_ref_entries) != 1:
        fail("image artifact must set exactly one DEVPKG_NIXPKGS_REF entry")
    if not re.fullmatch(r"DEVPKG_NIXPKGS_REF=path:/nix/store/[a-z0-9]{32}-source", devpkg_ref_entries[0]):
        fail("image artifact must pin DEVPKG_NIXPKGS_REF to the locked nixpkgs store source")
    locale_archive_entries = [entry for entry in env if entry.startswith("LOCALE_ARCHIVE=")]
    if len(locale_archive_entries) != 1:
        fail("image artifact must set exactly one LOCALE_ARCHIVE entry")
    locale_archive = locale_archive_entries[0].split("=", 1)[1]
    if "glibc-locales" not in locale_archive or not locale_archive.endswith("/lib/locale/locale-archive"):
        fail("image artifact must point LOCALE_ARCHIVE at glibcLocales")
    if any(entry.startswith("LC_ALL=") for entry in env):
        fail("image artifact must not set LC_ALL by default")
    for env_entry in env:
        if "$HOME" in env_entry or "$XDG_" in env_entry:
            fail("image artifact env must not retain unexpanded HOME/XDG references")

    labels = image_config.get("Labels")
    if not isinstance(labels, dict) or "devcontainer.metadata" not in labels:
        fail("image artifact must include devcontainer metadata")

    layers = image_json.get("layers")
    if not isinstance(layers, list) or not layers:
        fail("image artifact must contain at least one layer")
    for index, layer in enumerate(layers):
        if not isinstance(layer, dict):
            fail(f"layer {index} must be an object")
        layer_size = layer.get("size")
        if not isinstance(layer_size, int) or isinstance(layer_size, bool) or layer_size < 0:
            fail(f"{layer_label(index, layer)} must report a non-negative integer size")
        if layer_size > max_layer_size:
            fail(
                f"{layer_label(index, layer)} size {format_bytes(layer_size)} "
                f"exceeds max layer size {format_bytes(max_layer_size)}"
            )

    for text in walk_strings(image_json):
        if SENSITIVE_VALUE_RE.search(text):
            fail("image artifact appears to contain sensitive material")

    print(f"image-artifact-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
