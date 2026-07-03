#!/usr/bin/env python3
import pathlib
import sys

from layer_budget import BudgetError, check_layer_budget_files


def fail(message: str):
    print(f"layer-budget-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: tests/ci/check-layer-budget.py <nix2container-image-json> <reports-dir> <image-name>",
            file=sys.stderr,
        )
        return 1

    image_path = pathlib.Path(sys.argv[1])
    reports_dir = pathlib.Path(sys.argv[2])
    image_name = sys.argv[3]

    try:
        check_layer_budget_files(image_path, reports_dir)
    except FileNotFoundError as exc:
        fail(f"required file not found: {exc.filename}")
    except ValueError as exc:
        fail(str(exc))
    except BudgetError as exc:
        fail(str(exc))

    print(f"layer-budget-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
