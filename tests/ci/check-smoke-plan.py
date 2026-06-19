#!/usr/bin/env python3
import json
import pathlib
import re
import sys


COMMON = {
    "user-vscode",
    "filesystem-writable",
    "docker-client",
    "docker-buildx",
    "docker-compose",
    "docker-remote-version",
    "codex-version",
    "nix-index-tools",
    "fhs-ca-certificates",
}

REQUIRED = {
    "nix": COMMON
    | {
        "nix-version",
        "nixd-version",
        "nix-language",
        "extension-index",
        "task-runner-list",
        "devpkg-doctor",
        "fhs-bash",
        "fhs-os-release",
        "fhs-core-tools",
        "fhs-nix-ld",
    },
    "python": COMMON
    | {
        "python-version",
        "uv-version",
        "uvx-version",
        "python-runtime-imports",
        "python-node-runtime",
    },
    "nodejs": COMMON
    | {
        "node-version",
        "pnpm-version",
        "node-package-managers",
        "node-python-runtime",
        "node-c-env",
    },
    "go": COMMON
    | {
        "go-version",
        "gopls-version",
        "go-tooling",
        "go-runtime-deps",
    },
    "rust": COMMON
    | {
        "rustc-version",
        "cargo-version",
        "rust-tooling",
        "rust-runtime-deps",
    },
    "python-web": COMMON
    | {
        "python-web-stack",
        "python-web-formatters",
    },
    "go-web": COMMON
    | {
        "go-web-stack",
    },
    "rust-web": COMMON
    | {
        "rust-web-stack",
    },
    "flutter": COMMON
    | {
        "flutter-version",
        "dart-version",
        "flutter-tooling",
        "rust-tooling",
        "node-package-managers",
    },
}


def requirement_key(image_name: str) -> str:
    if image_name == "nix-latest":
        return "nix"
    if re.fullmatch(r"go-(latest|[0-9]+-[0-9]+)", image_name):
        return "go"
    if re.fullmatch(r"nodejs-(latest|[0-9]+)", image_name):
        return "nodejs"
    if image_name == "python3" or re.fullmatch(r"python-[0-9]+-[0-9]+", image_name):
        return "python"
    if image_name == "rust-latest":
        return "rust"
    if image_name == "flutter-latest":
        return "flutter"
    return image_name


def fail(message: str):
    print(f"smoke-plan-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: tests/ci/check-smoke-plan.py <smoke-plan.json> <image-name>", file=sys.stderr)
        return 1

    plan_path = pathlib.Path(sys.argv[1])
    image_name = sys.argv[2]

    with plan_path.open("r", encoding="utf-8") as handle:
        plan = json.load(handle)

    key = requirement_key(image_name)

    if key not in REQUIRED:
        fail(f"unsupported image in smoke plan: {image_name}")

    names = {test["name"] for test in plan["tests"]}
    expected = REQUIRED[key]
    missing = sorted(expected - names)
    if missing:
        fail(f"{image_name} missing tests: {', '.join(missing)}")

    print(f"smoke-plan-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
