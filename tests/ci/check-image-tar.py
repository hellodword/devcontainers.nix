#!/usr/bin/env python3
import json
import pathlib
import re
import sys

from layer_budget import BudgetError, check_layer_budget


SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)
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
    if len(sys.argv) != 5:
        print(
            "usage: tests/ci/check-image-tar.py <nix2container-image-json> <reports-dir> <image-name> <expected-devpkg-nixpkgs-ref>",
            file=sys.stderr,
        )
        return 1

    image_path = pathlib.Path(sys.argv[1])
    reports_dir = pathlib.Path(sys.argv[2])
    image_name = sys.argv[3]
    expected_devpkg_nixpkgs_ref = sys.argv[4]

    if not image_path.is_file():
        fail(f"image artifact is not a file: {image_path}")
    if image_path.stat().st_size == 0:
        fail("image artifact is empty")

    image_json = read_json(image_path)
    layer_plan = read_json(reports_dir / "layer-plan.json")
    layer_closure_report = read_json(reports_dir / "layer-closure-report.json")
    try:
        check_layer_budget(image_json, layer_plan, layer_closure_report)
    except BudgetError as exc:
        fail(str(exc))

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
    if not re.fullmatch(r"path:/nix/store/[a-z0-9]{32}-source", expected_devpkg_nixpkgs_ref):
        fail("expected DEVPKG_NIXPKGS_REF must be a locked nixpkgs store source")
    if devpkg_ref_entries[0] != f"DEVPKG_NIXPKGS_REF={expected_devpkg_nixpkgs_ref}":
        fail("image artifact must pin DEVPKG_NIXPKGS_REF to the locked nixpkgs store source")
    if not any(entry.startswith("DEVPKG_SYSTEM=") and entry.split("=", 1)[1] for entry in env):
        fail("image artifact must set DEVPKG_SYSTEM")
    if not any(entry.startswith("DEVPKG_NIXPKGS_CACHE_KEY=") and entry.split("=", 1)[1] for entry in env):
        fail("image artifact must set DEVPKG_NIXPKGS_CACHE_KEY")
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

    for text in walk_strings(image_json):
        if SENSITIVE_VALUE_RE.search(text):
            fail("image artifact appears to contain sensitive material")

    print(f"image-artifact-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
