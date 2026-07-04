#!/usr/bin/env python3
import json
import shutil
import subprocess
import sys
from pathlib import Path


USAGE = """devcontainer-image explain layer <n> [--report <dir>]
devcontainer-image explain package <name> [--report <dir>]
devcontainer-image explain extension <id> [--report <dir>]
devcontainer-image explain env <name> [--report <dir>]
devcontainer-image explain filesystem [--report <dir>]
devcontainer-image explain image-plan [--report <dir>]
devcontainer-image explain security [--report <dir>]
devcontainer-image diff <old-layer-plan.json> <new-layer-plan.json>
devcontainer-image check <metadata-label.json|devcontainer.json>
devcontainer-image doctor image <name>
"""


def usage(file=sys.stdout):
    print(USAGE, end="", file=file)


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def require_file(path: Path) -> None:
    if not path.is_file():
        fail(f"missing report file: {path}")


def read_json(path: Path):
    require_file(path)
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(value) -> None:
    print(json.dumps(value, indent=2, sort_keys=False))


def user_ok(value) -> bool:
    if not isinstance(value, dict):
        return False
    return (
        value.get("remoteUser", "vscode") == "vscode"
        and value.get("containerUser", "vscode") == "vscode"
        and value.get("updateRemoteUserUID", False) is not True
    )


def check_devcontainer_user(metadata_file: Path) -> None:
    metadata = read_json(metadata_file)
    ok = False
    if isinstance(metadata, list):
        ok = bool(metadata) and all(user_ok(item) for item in metadata)
    elif isinstance(metadata, dict):
        ok = user_ok(metadata)
    if not ok:
        fail(
            "devcontainers.nix images only support the vscode user; "
            "remove remoteUser/containerUser/updateRemoteUserUID overrides from devcontainer.json"
        )


def selected_report_args(argv: list[str]) -> tuple[Path, list[str]]:
    report_dir = Path(".")
    if len(argv) >= 2 and argv[-2] == "--report":
        report_dir = Path(argv[-1])
        argv = argv[:-2]
    return report_dir, argv


def explain(report_dir: Path, args: list[str]) -> int:
    topic = args[0] if args else ""
    target = args[1] if len(args) > 1 else ""
    if topic == "layer":
        layer_plan = read_json(report_dir / "layer-plan.json")
        try:
            index = int(target or "0")
            layer = layer_plan["layers"][index]
        except (ValueError, KeyError, IndexError, TypeError):
            fail(f"layer index not found: {target or '0'}")
        write_json(layer)
        return 0
    if topic == "package":
        closure_report = read_json(report_dir / "closure-report.json")
        for package in closure_report.get("packages") or []:
            if package == target:
                write_json(package)
                return 0
        fail(f"package not found: {target}")
    if topic == "extension":
        extensions_report = read_json(report_dir / "extensions-report.json")
        for extension in extensions_report.get("extensions") or []:
            if isinstance(extension, dict) and extension.get("id") == target:
                write_json(extension)
                return 0
        fail(f"extension not found: {target}")
    if topic == "env":
        env_report = read_json(report_dir / "env-report.json")
        if target == "PATH":
            value = (env_report.get("containerEnvSources") or {}).get("PATH")
        else:
            value = (
                (env_report.get("containerEnvSources") or {}).get(target)
                or (env_report.get("remoteEnvSources") or {}).get(target)
                or (env_report.get("shellEnvSources") or {}).get(target)
            )
        if value is None:
            fail(f"environment entry not found: {target}")
        write_json(value)
        return 0
    if topic in {
        "filesystem": "filesystem-report.json",
        "image-plan": "image-plan.json",
        "security": "security-report.json",
    }:
        path = report_dir / {
            "filesystem": "filesystem-report.json",
            "image-plan": "image-plan.json",
            "security": "security-report.json",
        }[topic]
        require_file(path)
        sys.stdout.write(path.read_text(encoding="utf-8"))
        return 0
    usage(sys.stderr)
    return 1


def layer_entry(layer: dict) -> dict:
    return {
        "group": layer.get("group"),
        "members": layer.get("members"),
        "priority": layer.get("priority"),
        "estimatedLayerSizeMiB": layer.get("estimatedLayerSizeMiB"),
    }


def layer_map(path: Path) -> dict:
    plan = read_json(path)
    layers = plan.get("layers")
    if not isinstance(layers, list):
        fail(f"layer plan must contain a layers array: {path}")
    return {layer_entry(layer).get("group"): layer_entry(layer) for layer in layers if isinstance(layer, dict)}


def diff_layers(old_file: Path, new_file: Path) -> int:
    old_layers = layer_map(old_file)
    new_layers = layer_map(new_file)
    added = []
    removed = []
    changed = []
    for group in sorted(set(old_layers) | set(new_layers), key=lambda value: "" if value is None else str(value)):
        before = old_layers.get(group)
        after = new_layers.get(group)
        if before is None:
            added.append({"group": after.get("group"), "after": after, "reasons": ["new layer"]})
            continue
        if after is None:
            removed.append({"group": before.get("group"), "before": before, "reasons": ["removed layer"]})
            continue
        reasons = []
        if before.get("members") != after.get("members"):
            reasons.append("members changed")
        if before.get("priority") != after.get("priority"):
            reasons.append("priority changed")
        if before.get("estimatedLayerSizeMiB") != after.get("estimatedLayerSizeMiB"):
            reasons.append("estimatedLayerSizeMiB changed")
        if reasons:
            changed.append({"group": after.get("group"), "before": before, "after": after, "reasons": reasons})
    write_json({"added": added, "removed": removed, "changed": changed})
    return 0


def doctor(args: list[str]) -> int:
    scope = args[0] if args else ""
    target = args[1] if len(args) > 1 else ""
    if scope != "image":
        usage(sys.stderr)
        return 1
    docker = shutil.which("docker")
    if docker:
        return subprocess.run([docker, "inspect", target]).returncode
    print(f"docker unavailable in current environment; inspect {target} elsewhere")
    return 0


def main(argv: list[str]) -> int:
    report_dir, args = selected_report_args(argv)
    cmd = args[0] if args else ""
    rest = args[1:]
    if cmd == "explain":
        return explain(report_dir, rest)
    if cmd == "diff":
        if len(rest) != 2:
            usage(sys.stderr)
            return 1
        return diff_layers(Path(rest[0]), Path(rest[1]))
    if cmd == "check":
        if len(rest) != 1:
            usage(sys.stderr)
            return 1
        check_devcontainer_user(Path(rest[0]))
        return 0
    if cmd == "doctor":
        return doctor(rest)
    usage(sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
