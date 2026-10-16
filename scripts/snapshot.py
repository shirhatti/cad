"""
Print-metrics snapshots: the "bundle size" of each model.

`scad-tools mesh` and `scad-tools slice` write per-model metrics to
artifacts/metrics/. `metrics snapshot` folds them into print-metrics.json,
which is committed, so a PR that changes a model shows its print-time,
filament, and support changes right in the diff. `metrics check` fails when
the committed snapshot is stale, and `metrics diff` renders the changes
between two snapshots as a Markdown table (CI posts it on the PR).
"""

import json
import sys
from pathlib import Path

import click

from scripts.expect import format_duration

SNAPSHOT_FILE = Path("print-metrics.json")
STAGES = ("mesh", "slice")

# Display order and formatting for the diff table; anything else is shown raw.
DISPLAY = {
    "time_s": ("print time", format_duration),
    "filament_g": ("filament", lambda v: f"{v:g} g"),
    "filament_m": ("filament length", lambda v: f"{v:g} m"),
    "supports": ("supports", lambda v: "yes" if v else "no"),
    "support_pct": ("support share", lambda v: f"{v:g}%"),
    "max_bridge_mm": ("longest bridge over air", lambda v: f"{v:g} mm"),
    "bridge_pct": ("bridge share", lambda v: f"{v:g}%"),
    "overhang_wall_pct": ("overhang wall share", lambda v: f"{v:g}%"),
    "layers": ("layers", str),
    "height_mm": ("height", lambda v: f"{v:g} mm"),
    "features": ("features", lambda v: ", ".join(v)),
    "fits_plate": ("fits plate", lambda v: "yes" if v else "no"),
    "volume_cm3": ("volume", lambda v: f"{v:g} cm³"),
    "size_mm": ("size", lambda v: " × ".join(f"{x:g}" for x in v) + " mm"),
    "bodies": ("bodies", str),
    "watertight": ("watertight", lambda v: "yes" if v else "no"),
    "min_wall_mm": ("thinnest wall", lambda v: f"{v:g} mm"),
    "overhang_mm2": ("overhang area", lambda v: f"{v:g} mm²"),
    "bed_contact_mm2": ("bed contact", lambda v: f"{v:g} mm²"),
}


# OrcaSlicer's estimates jitter slightly between identical runs (multithreaded
# support generation: seconds usually, ~1% at worst), so these compare within
# a tolerance: max(absolute floor, relative share). Everything else is exact.
NOISY = {
    "time_s": 60,
    "filament_g": 0.5,
    "filament_m": 0.2,
    "support_pct": 0.5,
    "bridge_pct": 0.2,
    "overhang_wall_pct": 0.2,
    "max_bridge_mm": 1.0,
}
REL_TOLERANCE = 0.02


def same(key: str, old, new) -> bool:
    """Whether a metric is unchanged, allowing estimator jitter for NOISY keys."""
    if key in NOISY and isinstance(old, (int, float)) and isinstance(new, (int, float)):
        return abs(new - old) <= max(NOISY[key], REL_TOLERANCE * max(abs(old), abs(new)))
    return old == new


def stabilize(before: dict, current: dict) -> dict:
    """current, but keeping before's value wherever it's within tolerance."""
    out = {}
    for model, stages in current.items():
        out[model] = {}
        for stage, values in stages.items():
            old = before.get(model, {}).get(stage, {})
            out[model][stage] = {
                k: old[k] if k in old and same(k, old[k], v) else v for k, v in values.items()
            }
    return out


def model_rel_path(model_name: str) -> str:
    """Output name -> model path: "rack__bracket" -> "rack/bracket.scad"."""
    return "/".join(model_name.rsplit("__", 1)) + ".scad"


def collect(metrics_dir: Path) -> dict:
    """Fold artifacts/metrics/<model>.<stage>.json into one snapshot dict."""
    snapshot: dict[str, dict] = {}
    for stage in STAGES:
        for path in sorted(metrics_dir.glob(f"*.{stage}.json")):
            model = model_rel_path(path.name.removesuffix(f".{stage}.json"))
            snapshot.setdefault(model, {})[stage] = json.loads(path.read_text())
    return dict(sorted(snapshot.items()))


def dumps(snapshot: dict) -> str:
    return json.dumps(snapshot, indent=2, sort_keys=True) + "\n"


def load(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text() or "{}")
    except json.JSONDecodeError as e:
        raise click.ClickException(f"{path} is not valid JSON: {e}")


def _fmt(key: str, value) -> str:
    if value is None:
        return "—"
    _, fmt = DISPLAY.get(key, (key, None))
    if fmt is None:
        return ", ".join(value) if isinstance(value, list) else str(value)
    return fmt(value)


def _delta(old, new) -> str:
    if isinstance(old, bool) or isinstance(new, bool):
        return ""
    if isinstance(old, (int, float)) and isinstance(new, (int, float)) and old:
        return f"{(new - old) / abs(old) * 100:+.0f}%"
    if isinstance(old, list) and isinstance(new, list) and all(isinstance(x, str) for x in old + new):
        added = [f"+{x}" for x in new if x not in old]
        removed = [f"−{x}" for x in old if x not in new]
        return ", ".join(added + removed)
    return ""


def diff_rows(before: dict, after: dict) -> list[tuple[str, str, str, str, str]]:
    """(model, metric, before, after, delta) for every changed value."""
    rows = []
    for model in sorted(set(before) | set(after)):
        if model not in after:
            rows.append((model, "model", "present", "removed", ""))
            continue
        if model not in before:
            rows.append((model, "model", "—", "new", ""))
        for stage in STAGES:
            old = before.get(model, {}).get(stage, {})
            new = after[model].get(stage, {})
            keys = [k for k in DISPLAY if k in old or k in new]
            keys += sorted(k for k in set(old) | set(new) if k not in DISPLAY)
            for key in keys:
                if not same(key, old.get(key), new.get(key)):
                    label = DISPLAY.get(key, (key, None))[0]
                    rows.append((
                        model, f"{stage}: {label}", _fmt(key, old.get(key)),
                        _fmt(key, new.get(key)), _delta(old.get(key), new.get(key)),
                    ))
    return rows


def markdown_report(before: dict, after: dict, title: str = "Print metrics") -> str:
    rows = diff_rows(before, after)
    out = [f"### {title}", ""]
    if not rows:
        out.append(f"No print-metric changes across {len(after)} model(s).")
        return "\n".join(out) + "\n"
    changed = sorted({r[0] for r in rows})
    out.append(f"{len(changed)} of {len(set(before) | set(after))} model(s) changed.")
    out += ["", "| Model | Metric | Before | After | Δ |", "|---|---|---|---|---|"]
    last = None
    for model, metric, old, new, delta in rows:
        out.append(f"| {'`' + model + '`' if model != last else ''} | {metric} | {old} | {new} | {delta} |")
        last = model
    return "\n".join(out) + "\n"


@click.group()
def metrics() -> None:
    """Snapshot and diff per-model print metrics."""


@metrics.command()
@click.option("--metrics-dir", type=click.Path(path_type=Path), default=Path("artifacts/metrics"))
@click.option("--output", type=click.Path(path_type=Path), default=SNAPSHOT_FILE, show_default=True)
def snapshot(metrics_dir: Path, output: Path) -> None:
    """Write the current metrics to the committed snapshot file."""
    current = collect(metrics_dir)
    if not current:
        raise click.ClickException(f"No metrics in {metrics_dir}; run `scad-tools mesh` and `scad-tools slice` first")
    before = load(output)
    current = stabilize(before, current)
    output.write_text(dumps(current))
    click.echo(markdown_report(before, current, f"Changes to {output}"))
    click.secho(f"✓ Wrote {len(current)} model(s) to {output}", fg="green")


@metrics.command()
@click.argument("before", type=click.Path(path_type=Path))
@click.argument("after", type=click.Path(path_type=Path), required=False)
@click.option("--metrics-dir", type=click.Path(path_type=Path), default=Path("artifacts/metrics"))
@click.option("--title", default="Print metrics")
def diff(before: Path, after: Path | None, metrics_dir: Path, title: str) -> None:
    """Markdown table of metric changes from BEFORE to AFTER.

    BEFORE/AFTER are snapshot files; AFTER defaults to the fresh metrics in
    --metrics-dir. A missing BEFORE counts as empty (every model is new).
    """
    current = load(after) if after else collect(metrics_dir)
    click.echo(markdown_report(load(before), current, title), nl=False)


@metrics.command()
@click.option("--metrics-dir", type=click.Path(path_type=Path), default=Path("artifacts/metrics"))
@click.option("--snapshot", "snapshot_file", type=click.Path(path_type=Path), default=SNAPSHOT_FILE, show_default=True)
def check(metrics_dir: Path, snapshot_file: Path) -> None:
    """Fail if the committed snapshot doesn't match the fresh metrics.

    Estimates (print time, filament, support share) match within a small
    tolerance, since the slicer jitters slightly between identical runs.
    """
    current = collect(metrics_dir)
    committed = load(snapshot_file)
    if not diff_rows(committed, current):
        click.secho(f"✓ {snapshot_file} is up to date ({len(current)} model(s))", fg="green")
        return
    click.echo(markdown_report(committed, current, f"{snapshot_file} is out of date"))
    click.secho(
        f"✗ {snapshot_file} doesn't match this build. Run `just snapshot` (or "
        f"`uv run scad-tools metrics snapshot` after mesh + slice) and commit it.",
        fg="red", err=True,
    )
    sys.exit(1)
