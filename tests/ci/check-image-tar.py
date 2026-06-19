#!/usr/bin/env python3
import json
import pathlib
import re
import sys


SENSITIVE_VALUE_RE = re.compile(
    r"(?i)(?:token|password|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*(?:=|:)\s*[\"']?[^\"'\\s]+"
)


def fail(message: str):
    print(f"image-artifact-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


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
    if len(sys.argv) != 3:
        print("usage: tests/ci/check-image-tar.py <nix2container-image-json> <image-name>", file=sys.stderr)
        return 1

    image_path = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    if not image_path.is_file():
        fail(f"image artifact is not a file: {image_path}")
    if image_path.stat().st_size == 0:
        fail("image artifact is empty")

    try:
        image_json = json.loads(image_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"image artifact must be nix2container JSON: {exc}")

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

    env = image_config.get("Env")
    if not isinstance(env, list) or "HOME=/home/vscode" not in env:
        fail("image artifact must set HOME for the vscode user")
    for required_env in [
        "XDG_CONFIG_HOME=/home/vscode/.config",
        "XDG_CACHE_HOME=/home/vscode/.cache",
        "XDG_DATA_HOME=/home/vscode/.local/share",
        "XDG_STATE_HOME=/home/vscode/.local/state",
        "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
        "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt",
        "CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt",
        "GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt",
    ]:
        if required_env not in env:
            fail(f"image artifact must set expanded {required_env.split('=', 1)[0]}")
    for env_entry in env:
        if "$HOME" in env_entry or "$XDG_" in env_entry:
            fail("image artifact env must not retain unexpanded HOME/XDG references")

    labels = image_config.get("Labels")
    if not isinstance(labels, dict) or "devcontainer.metadata" not in labels:
        fail("image artifact must include devcontainer metadata")

    layers = image_json.get("layers")
    if not isinstance(layers, list) or not layers:
        fail("image artifact must contain at least one layer")

    for text in walk_strings(image_json):
        if SENSITIVE_VALUE_RE.search(text):
            fail("image artifact appears to contain sensitive material")

    print(f"image-artifact-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
