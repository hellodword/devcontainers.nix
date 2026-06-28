#!/usr/bin/env python3
"""Guard default checks against host-dependent shortcuts.

The default flake checks must stay hermetic: they should not call the nix CLI
or nix-store, add pkgs.nix to derivations, or seed PATH from host
/usr/bin:/bin. Those shortcuts make checks depend on the host environment or a
running Nix daemon instead of the derivation closure being tested.
"""

import pathlib
import re
import sys


REPO_ROOT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(".")
SCAN_DIRS = [
    REPO_ROOT / "flake" / "checks",
    REPO_ROOT / "tests" / "ci",
]
SELF_SOURCE_NAME = "check-hermetic-default-checks.py"

FORBIDDEN_PATTERNS = [
    (
        re.compile(r"\bnix-store\b"),
        "default check builders must not call nix-store",
    ),
    (
        re.compile(r"\bnix\s+(build|profile|eval|search|run|shell|develop)\b"),
        "default check builders must not call the nix CLI",
    ),
    (
        re.compile(r"\bpkgs\.nix\b"),
        "default check derivations must not add pkgs.nix",
    ),
    (
        re.compile(r"PATH=(['\"])?/usr/bin:/bin\b"),
        "default checks must not seed PATH from host /usr/bin:/bin",
    ),
]


def fail(path: pathlib.Path, line_no: int, message: str, line: str):
    rel = path.relative_to(REPO_ROOT)
    print(f"{rel}:{line_no}: {message}: {line.rstrip()}", file=sys.stderr)
    raise SystemExit(1)


def iter_files():
    for root in SCAN_DIRS:
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            if path.name == SELF_SOURCE_NAME:
                continue
            if path.suffix not in {".nix", ".sh", ".py"}:
                continue
            yield path


def check_file(path: pathlib.Path):
    text = path.read_text(encoding="utf-8")
    for line_no, line in enumerate(text.splitlines(), start=1):
        if line_no > 1 and line.startswith("#!/usr/bin/env"):
            fail(path, line_no, "generated executables must use an absolute Nix-store interpreter", line)
        if "fake nix" in line:
            continue
        for pattern, message in FORBIDDEN_PATTERNS:
            if pattern.search(line):
                fail(path, line_no, message, line)


def main() -> int:
    for path in iter_files():
        check_file(path)
    print("hermetic-default-checks ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
