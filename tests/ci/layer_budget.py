import json
import pathlib
import re
from decimal import Decimal, InvalidOperation, ROUND_CEILING


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
SEMANTIC_CREATED_BY_PREFIX = "devcontainers.nix semantic layer "


class BudgetError(Exception):
    pass


def read_json(path: pathlib.Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_size_bytes(value) -> int:
    if isinstance(value, bool):
        raise BudgetError("layer budget maxLayerSize must be a size string or positive integer")
    if isinstance(value, int):
        if value <= 0:
            raise BudgetError("layer budget maxLayerSize must be positive")
        return value
    if not isinstance(value, str):
        raise BudgetError("layer budget maxLayerSize must be a size string or positive integer")

    match = SIZE_RE.match(value)
    if not match:
        raise BudgetError(f"layer budget maxLayerSize has unsupported format: {value}")

    try:
        number = Decimal(match.group(1))
    except InvalidOperation:
        raise BudgetError(f"layer budget maxLayerSize has unsupported number: {value}")

    if number <= 0:
        raise BudgetError("layer budget maxLayerSize must be positive")

    unit = (match.group(2) or "").lower()
    multiplier = SIZE_UNITS.get(unit)
    if multiplier is None:
        raise BudgetError(f"layer budget maxLayerSize has unsupported unit: {value}")

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


def _positive_int(value, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise BudgetError(f"{label} must be an integer")
    if value < 1:
        raise BudgetError(f"{label} must be at least 1")
    return value


def _non_negative_int(value, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise BudgetError(f"{label} must be an integer")
    if value < 0:
        raise BudgetError(f"{label} must be non-negative")
    return value


def parse_budget(layer_plan: dict) -> dict:
    budget = layer_plan.get("budget")
    if not isinstance(budget, dict):
        raise BudgetError("layer-plan.json budget must be an object")

    max_layers = _positive_int(budget.get("max"), "layer budget max")
    reserve = _non_negative_int(budget.get("reserve", 0), "layer budget reserve")
    default_semantic_max = max_layers - reserve
    semantic_max = budget.get("semanticMax", default_semantic_max)
    semantic_max = _non_negative_int(semantic_max, "layer budget semanticMax")
    if semantic_max > max_layers:
        raise BudgetError("layer budget semanticMax must not exceed max")
    if reserve > max_layers:
        raise BudgetError("layer budget reserve must not exceed max")

    max_layer_size = parse_size_bytes(budget.get("maxLayerSize"))
    return {
        "max": max_layers,
        "reserve": reserve,
        "semanticMax": semantic_max,
        "maxLayerSize": max_layer_size,
    }


def semantic_layer_groups(image_layers: list) -> list[str]:
    groups = []
    for layer in image_layers:
        history = layer.get("History") if isinstance(layer.get("History"), dict) else {}
        created_by = history.get("created_by")
        if isinstance(created_by, str) and created_by.startswith(SEMANTIC_CREATED_BY_PREFIX):
            groups.append(created_by[len(SEMANTIC_CREATED_BY_PREFIX) :])
    return groups


def planned_layer_groups(layer_plan: dict) -> list[str]:
    order = layer_plan.get("order")
    if isinstance(order, list) and all(isinstance(group, str) and group for group in order):
        return order
    layers = layer_plan.get("layers")
    if not isinstance(layers, list):
        raise BudgetError("layer-plan.json layers must be an array")
    groups = [layer.get("group") for layer in layers if isinstance(layer, dict)]
    if not all(isinstance(group, str) and group for group in groups):
        raise BudgetError("layer-plan.json layers must include non-empty group names")
    return groups


def check_layer_budget(image_json: dict, layer_plan: dict, closure_report: dict | None = None) -> None:
    budget = parse_budget(layer_plan)
    planned_groups = planned_layer_groups(layer_plan)

    image_layers = image_json.get("layers")
    if not isinstance(image_layers, list) or not image_layers:
        raise BudgetError("image artifact must contain at least one layer")
    if len(image_layers) > budget["max"]:
        raise BudgetError(f"image layer count {len(image_layers)} exceeds budget {budget['max']}")

    for index, layer in enumerate(image_layers):
        if not isinstance(layer, dict):
            raise BudgetError(f"layer {index} must be an object")
        layer_size = layer.get("size")
        if not isinstance(layer_size, int) or isinstance(layer_size, bool) or layer_size < 0:
            raise BudgetError(f"{layer_label(index, layer)} must report a non-negative integer size")
        if layer_size > budget["maxLayerSize"]:
            raise BudgetError(
                f"{layer_label(index, layer)} size {format_bytes(layer_size)} "
                f"exceeds max layer size {format_bytes(budget['maxLayerSize'])}"
            )

    semantic_groups = semantic_layer_groups(image_layers)
    if len(semantic_groups) > budget["semanticMax"]:
        raise BudgetError(
            f"semantic layer count {len(semantic_groups)} exceeds budget {budget['semanticMax']}"
        )
    if semantic_groups != planned_groups:
        raise BudgetError(
            "image semantic layer groups do not match layer-plan.json order: "
            f"{semantic_groups!r} != {planned_groups!r}"
        )

    if closure_report is None:
        return

    if closure_report.get("budget") != layer_plan.get("budget"):
        raise BudgetError("layer-closure-report.json budget must match layer-plan.json")
    if closure_report.get("order") != planned_groups:
        raise BudgetError("layer-closure-report.json order must match layer-plan.json")

    closure_layers = closure_report.get("layers")
    if not isinstance(closure_layers, list):
        raise BudgetError("layer-closure-report.json layers must be an array")
    closure_groups = [layer.get("group") for layer in closure_layers if isinstance(layer, dict)]
    if closure_groups != planned_groups:
        raise BudgetError("layer-closure-report.json layers must match layer-plan.json groups")

    for layer in closure_layers:
        for field in ["closureSizeBytes", "closurePathCount", "rootPathCount"]:
            value = layer.get(field)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise BudgetError(f"layer-closure-report.json {layer.get('group')} {field} must be non-negative")
        closure_paths = layer.get("closureStorePaths")
        if not isinstance(closure_paths, list) or not all(isinstance(path, str) for path in closure_paths):
            raise BudgetError(
                f"layer-closure-report.json {layer.get('group')} closureStorePaths must contain strings"
            )


def check_layer_budget_files(image_path: pathlib.Path, reports_dir: pathlib.Path) -> None:
    image_json = read_json(image_path)
    layer_plan = read_json(reports_dir / "layer-plan.json")
    closure_report_path = reports_dir / "layer-closure-report.json"
    closure_report = read_json(closure_report_path) if closure_report_path.is_file() else None
    check_layer_budget(image_json, layer_plan, closure_report)
