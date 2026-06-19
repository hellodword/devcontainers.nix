#!/usr/bin/env python3
import json
import pathlib
import sys


REQUIRED = {
    "nix": {
        "extension-index",
        "task-runner-list",
        "devpkg-doctor",
        "fhs-bash",
        "fhs-os-release",
        "fhs-core-tools",
    },
    "nix-dind": {
        "docker-version",
        "docker-info",
        "docker-buildx",
        "docker-compose",
        "docker-build-run",
    },
    "python": {
        "python-version",
        "uv-version",
        "uvx-version",
        "python-runtime-imports",
        "python-node-runtime",
    },
    "nodejs": {
        "node-version",
        "pnpm-version",
        "node-package-managers",
        "node-python-runtime",
        "node-c-env",
    },
    "go": {
        "go-version",
        "gopls-version",
        "go-tooling",
        "go-runtime-deps",
    },
    "rust": {
        "rustc-version",
        "cargo-version",
        "rust-tooling",
        "rust-runtime-deps",
    },
    "python-web": {
        "python-web-stack",
        "python-web-formatters",
    },
    "go-web": {
        "go-web-stack",
    },
    "rust-web": {
        "rust-web-stack",
    },
    "flutter": {
        "flutter-version",
        "dart-version",
        "flutter-tooling",
        "rust-tooling",
        "node-package-managers",
    },
}


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

    names = {test["name"] for test in plan["tests"]}
    expected = REQUIRED[image_name]
    missing = sorted(expected - names)
    if missing:
        fail(f"{image_name} missing tests: {', '.join(missing)}")

    print(f"smoke-plan-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
