#!/usr/bin/env python3
import json
import pathlib
import sys

from jsonschema import Draft7Validator, RefResolver
from jsonschema.exceptions import ValidationError


def fail(message: str):
    print(f"devcontainer-metadata-schema-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: pathlib.Path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        fail(f"required JSON file not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def format_error(error: ValidationError) -> str:
    location = "/".join(str(part) for part in error.absolute_path)
    if not location:
        location = "<root>"
    return f"{location}: {error.message}"


def validate_document(validator: Draft7Validator, value, context: str):
    errors = sorted(validator.iter_errors(value), key=lambda error: list(error.absolute_path))
    if errors:
        fail(f"{context} does not match devContainer.base.schema.json: {format_error(errors[0])}")


def main() -> int:
    if len(sys.argv) != 5:
        print(
            "usage: check-devcontainer-metadata-schema.py "
            "<metadata-label.json> <metadata-merged-preview.json> <schema-dir> <image-name>",
            file=sys.stderr,
        )
        return 2

    label_path = pathlib.Path(sys.argv[1])
    preview_path = pathlib.Path(sys.argv[2])
    schema_dir = pathlib.Path(sys.argv[3])
    image_name = sys.argv[4]

    schema_path = schema_dir / "devContainer.base.schema.json"
    schema = read_json(schema_path)
    label = read_json(label_path)
    preview = read_json(preview_path)

    if not isinstance(label, list) or not label:
        fail(f"{image_name}: metadata-label.json must be a non-empty JSON array")
    if not isinstance(preview, dict):
        fail(f"{image_name}: metadata-merged-preview.json must be a JSON object")

    resolver = RefResolver(
        base_uri=schema_path.resolve().as_uri(),
        referrer=schema,
        store={schema_path.resolve().as_uri(): schema},
    )
    validator = Draft7Validator(schema, resolver=resolver)

    for index, snippet in enumerate(label):
        if not isinstance(snippet, dict):
            fail(f"{image_name}: metadata-label.json snippet {index} must be a JSON object")
        validate_document(validator, snippet, f"{image_name}: metadata-label.json snippet {index}")
    validate_document(validator, preview, f"{image_name}: metadata-merged-preview.json")

    print(f"devcontainer-metadata-schema-check ok: {image_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
