#!/usr/bin/env python3
import json
import pathlib
import sys
import xml.etree.ElementTree as ET


def fail(message: str):
    print(f"fontconfig-root-check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_json(path: pathlib.Path):
    try:
        with path.open("r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        fail(f"required JSON file not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def child_families(alias: ET.Element, name: str) -> list[str]:
    child = alias.find(name)
    if child is None:
        return []
    return [(family.text or "") for family in child.findall("family")]


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: check-fontconfig-root.py <font-root> <fontconfig-report.json> <image-name>",
            file=sys.stderr,
        )
        return 2

    font_root = pathlib.Path(sys.argv[1])
    report_path = pathlib.Path(sys.argv[2])
    image_name = sys.argv[3]
    alias_path = font_root / "etc/fonts/conf.d/53-devcontainer-aliases.conf"

    if not alias_path.exists():
        fail(f"{image_name}: missing /etc/fonts/conf.d/53-devcontainer-aliases.conf")

    report = read_json(report_path)
    aliases = ((report.get("fontconfig") or {}).get("aliases") or {})
    helvetica = aliases.get("Helvetica")
    if helvetica is None:
        fail(f"{image_name}: fontconfig report missing synthetic Helvetica alias")

    try:
        root = ET.parse(alias_path).getroot()
    except ET.ParseError as exc:
        fail(f"{image_name}: invalid generated fontconfig XML: {exc}")

    matches = []
    for alias in root.findall("alias"):
        family = alias.find("family")
        if (family.text if family is not None else None) == "Helvetica":
            matches.append(alias)

    if not matches:
        fail(f"{image_name}: generated XML missing Helvetica alias")

    expected = {
        "binding": "strong",
        "prefer": ["Noto Sans"],
        "accept": ["Noto Sans CJK SC"],
        "default": ["sans-serif"],
    }

    for alias in matches:
        if alias.attrib.get("binding") != expected["binding"]:
            continue
        if child_families(alias, "prefer") != expected["prefer"]:
            continue
        if child_families(alias, "accept") != expected["accept"]:
            continue
        if child_families(alias, "default") != expected["default"]:
            continue
        print(f"fontconfig-root-check ok: {image_name}")
        return 0

    fail(
        f"{image_name}: generated Helvetica alias must include binding=strong, "
        "prefer=Noto Sans, accept=Noto Sans CJK SC, and default=sans-serif"
    )


if __name__ == "__main__":
    raise SystemExit(main())
