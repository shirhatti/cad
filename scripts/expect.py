"""
Per-model print expectations: the "type annotations" of a printable model.

Declared in pyproject.toml, keyed by model path relative to the projects dir:

    [tool.scad-tools.expect.defaults]      # apply to every model
    watertight = true
    bodies = 1

    [tool.scad-tools.expect.models."rack/apple_tv_retention_bracket.scad"]
    max_time = "2h15m"
    supports = true

Mesh rules are checked by `scad-tools mesh` against the STL; slice rules by
`scad-tools slice` against the sliced 3MF. Unknown keys are errors, so a typo
can't silently disable a check.
"""

import re
import tomllib
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import click


@dataclass(frozen=True)
class Rule:
    stage: str  # "mesh" or "slice": which metrics it reads
    metric: str
    kind: str  # "eq" (must equal), "max" (upper bound), "min" (lower bound)
    parse: Callable = lambda v: v
    fmt: Callable = lambda v: f"{v}"
    help: str = ""


def parse_duration(value) -> int:
    """Seconds from 5400, "90m", "1h30m", or "1h 30m 10s"."""
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return int(value)
    if isinstance(value, str):
        parts = re.findall(r"(\d+(?:\.\d+)?)\s*([hms])", value.lower())
        if parts and re.fullmatch(r"(\s*\d+(?:\.\d+)?\s*[hms])+\s*", value.lower()):
            scale = {"h": 3600, "m": 60, "s": 1}
            return int(sum(float(n) * scale[u] for n, u in parts))
    raise ValueError(f"not a duration: {value!r} (use e.g. \"1h30m\")")


def format_duration(seconds) -> str:
    seconds = int(seconds)
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h}h{m:02d}m" if h else f"{m}m{s:02d}s"


def _bool(v):
    if not isinstance(v, bool):
        raise ValueError(f"expected true/false, got {v!r}")
    return v


def _int(v):
    if isinstance(v, bool) or not isinstance(v, int):
        raise ValueError(f"expected an integer, got {v!r}")
    return v


def _num(v):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise ValueError(f"expected a number, got {v!r}")
    return float(v)


RULES: dict[str, Rule] = {
    # Mesh (STL) rules
    "watertight": Rule("mesh", "watertight", "eq", _bool, help="closed, manifold surface"),
    "bodies": Rule("mesh", "bodies", "eq", _int, help="separate printed parts"),
    "fits_plate": Rule("mesh", "fits_plate", "eq", _bool, help="bounding box fits the build volume"),
    "min_wall_mm": Rule("mesh", "min_wall_mm", "min", _num, lambda v: f"{v:g} mm", "thinnest 1% of walls"),
    "max_overhang_mm2": Rule("mesh", "overhang_mm2", "max", _num, lambda v: f"{v:g} mm²", ">45° unsupported area"),
    "min_bed_contact_mm2": Rule("mesh", "bed_contact_mm2", "min", _num, lambda v: f"{v:g} mm²", "first-layer adhesion"),
    # Slice (3MF) rules
    "max_time": Rule("slice", "time_s", "max", parse_duration, format_duration, "predicted print time"),
    "max_filament_g": Rule("slice", "filament_g", "max", _num, lambda v: f"{v:g} g", "filament weight"),
    "supports": Rule("slice", "supports", "eq", _bool, help="slicer generated supports"),
    "max_support_pct": Rule("slice", "support_pct", "max", _num, lambda v: f"{v:g}%", "support share of extrusion"),
    "max_bridge_mm": Rule("slice", "max_bridge_mm", "max", _num, lambda v: f"{v:g} mm", "longest bridge line"),
    "max_overhang_wall_pct": Rule("slice", "overhang_wall_pct", "max", _num, lambda v: f"{v:g}%", "overhang wall share"),
}


def load_expectations(base_path: Path, pyproject: Path = Path("pyproject.toml")) -> tuple[dict, dict]:
    """
    Returns (defaults, models) with values parsed, where models maps a model
    path relative to base_path (e.g. "rack/x.scad") to its own rules. Raises
    ClickException on unknown keys or bad values; warns on unknown models.
    """
    if not pyproject.exists():
        return {}, {}
    try:
        with open(pyproject, "rb") as f:
            config = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        raise click.ClickException(f"Can't read expectations from {pyproject}: {e}")
    section = config.get("tool", {}).get("scad-tools", {}).get("expect", {})

    def parse_table(where: str, table) -> dict:
        if not isinstance(table, dict):
            raise click.ClickException(f"{where} must be a table")
        out = {}
        for key, value in table.items():
            rule = RULES.get(key)
            if rule is None:
                known = ", ".join(sorted(RULES))
                raise click.ClickException(f"{where}: unknown expectation {key!r} (known: {known})")
            try:
                out[key] = rule.parse(value)
            except ValueError as e:
                raise click.ClickException(f"{where}.{key}: {e}")
        return out

    unknown = set(section) - {"defaults", "models"}
    if unknown:
        raise click.ClickException(f"[tool.scad-tools.expect]: unknown table(s) {sorted(unknown)}")
    defaults = parse_table("[tool.scad-tools.expect.defaults]", section.get("defaults", {}))
    models = {}
    for path, table in section.get("models", {}).items():
        models[path] = parse_table(f'[tool.scad-tools.expect.models."{path}"]', table)
        if not (base_path / path).is_file():
            click.secho(f"⚠ Expectations match no model: {base_path / path}", fg="yellow", err=True)
    return defaults, models


def expectations_for(model_path: str, defaults: dict, models: dict) -> dict:
    return {**defaults, **models.get(model_path, {})}


def evaluate(stage: str, metrics: dict, expected: dict) -> list[str]:
    """Human-readable failures for one model's rules of this stage."""
    failures = []
    for key, want in expected.items():
        rule = RULES[key]
        if rule.stage != stage:
            continue
        have = metrics.get(rule.metric)
        if have is None:
            failures.append(f"{key}: no {rule.metric} measured, can't check {rule.fmt(want)}")
        elif rule.kind == "eq" and have != want:
            failures.append(f"{key}: expected {want}, got {have} ({rule.help})")
        elif rule.kind == "max" and have > want:
            failures.append(f"{key}: {rule.fmt(have)} is over the budget of {rule.fmt(want)} ({rule.help})")
        elif rule.kind == "min" and have < want:
            failures.append(f"{key}: {rule.fmt(have)} is under the minimum of {rule.fmt(want)} ({rule.help})")
    return failures
