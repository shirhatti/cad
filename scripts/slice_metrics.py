"""
Metrics read back out of a sliced 3MF: the slicer's own summary
(Metadata/slice_info.config), the settings it actually used
(Metadata/project_settings.config), and a single pass over the annotated
G-code (layers, per-feature extrusion, bridge spans).
"""

import json
import math
import re
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

SLICE_INFO = "Metadata/slice_info.config"
PROJECT_SETTINGS = "Metadata/project_settings.config"
PLATE_GCODE = "Metadata/plate_1.gcode"

SUPPORT_FEATURES = {"Support", "Support interface", "Support transition"}
# External bridges span air; "Internal Bridge" spans sparse infill and is short
BRIDGE_FEATURES = {"Bridge"}

# A bridge line counts as resting on support where support was printed within
# this XY distance on one of the few layers below it (support sits a top-z
# gap below the part, so the layer directly under may be empty).
SUPPORT_GRID_MM = 2.0
SUPPORT_LOOKBACK_LAYERS = 3
SAMPLE_STEP_MM = 0.5

_WORD_RE = re.compile(r"([A-Z])(-?\d*\.?\d+)")


def effective_settings(threemf: Path) -> dict:
    """The full config the slicer used for this plate."""
    with zipfile.ZipFile(threemf) as z:
        return json.loads(z.read(PROJECT_SETTINGS))


def slice_info(threemf: Path) -> dict:
    """
    Plate summary: predicted time, filament weight/length, plate fit. (Its
    support_used flag means support is *enabled*, so `supports` comes from the
    G-code instead.)
    """
    with zipfile.ZipFile(threemf) as z:
        root = ET.fromstring(z.read(SLICE_INFO))
    plate = root.find("plate")
    if plate is None:
        raise ValueError(f"no <plate> in {SLICE_INFO}")
    meta = {m.get("key"): m.get("value") for m in plate.findall("metadata")}
    filaments = plate.findall("filament")

    def num(value: str | None) -> float | None:
        try:
            return float(value) if value not in (None, "") else None
        except ValueError:
            return None

    return {
        "time_s": num(meta.get("prediction")),
        "filament_g": num(meta.get("weight")),
        "filament_m": round(sum(num(f.get("used_m")) or 0 for f in filaments), 2),
        "fits_plate": meta.get("outside") == "false",
    }


def _samples(x0, y0, x1, y1):
    length = math.hypot(x1 - x0, y1 - y0)
    n = max(1, int(length / SAMPLE_STEP_MM))
    return length, [(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n) for k in range(n + 1)]


def _cell(px, py) -> tuple[int, int]:
    return (int(px // SUPPORT_GRID_MM), int(py // SUPPORT_GRID_MM))


def _unsupported_run(x0, y0, x1, y1, below: set) -> float:
    """Longest stretch of a straight line with no support cell (or neighbor) below."""
    length, points = _samples(x0, y0, x1, y1)
    step = length / max(1, len(points) - 1)
    best = run = 0.0
    for px, py in points:
        cx, cy = _cell(px, py)
        covered = any((cx + dx, cy + dy) in below for dx in (-1, 0, 1) for dy in (-1, 0, 1))
        run = 0.0 if covered else run + step
        best = max(best, run)
    return min(best, length)


def gcode_metrics(gcode: str) -> dict:
    """
    Walk the G-code once, tracking position, extrusion mode, and the slicer's
    `; FEATURE:` annotations. Extrusion is summed per feature (positive E only,
    so retractions and wipes don't count).

    Bridges: the slicer also uses bridge flow for the first layer over support
    interface, so the longest Bridge line says little on its own. max_bridge_mm
    is the longest run of a Bridge line with no support printed beneath it in
    the last few layers, i.e. the longest span actually over air. (Arcs count
    as their chord, which only shortens the estimate for curved bridges.)
    """
    x = y = 0.0
    e_abs = 0.0
    relative_e = True  # Bambu start G-code uses M83; M82 switches back
    feature = None
    layers = 0
    max_z = 0.0
    extruded: dict[str, float] = {}
    longest_bridge = 0.0
    support_cells: list[set] = [set()]  # per layer, newest last

    for raw in gcode.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line[0] == ";":
            if line.startswith("; FEATURE:"):
                feature = line[len("; FEATURE:"):].strip()
            elif line.startswith("; CHANGE_LAYER"):
                layers += 1
                support_cells = support_cells[-SUPPORT_LOOKBACK_LAYERS:] + [set()]
            elif line.startswith("; Z_HEIGHT:"):
                try:
                    max_z = max(max_z, float(line.split(":", 1)[1]))
                except ValueError:
                    pass
            continue
        code = line.split(";", 1)[0].split()
        if not code:
            continue
        cmd = code[0]
        if cmd == "M83":
            relative_e = True
            continue
        if cmd == "M82":
            relative_e = False
            continue
        words = {m.group(1): float(m.group(2)) for m in _WORD_RE.finditer(" ".join(code[1:]))}
        if cmd == "G92":
            if "E" in words:
                e_abs = words["E"]
            continue
        if cmd not in ("G0", "G1", "G2", "G3"):
            continue

        nx, ny = words.get("X", x), words.get("Y", y)
        de = 0.0
        if "E" in words:
            de = words["E"] if relative_e else words["E"] - e_abs
            e_abs = e_abs + words["E"] if relative_e else words["E"]
        if de > 0 and feature:
            extruded[feature] = extruded.get(feature, 0.0) + de
            if feature in SUPPORT_FEATURES:
                support_cells[-1].update(_cell(px, py) for px, py in _samples(x, y, nx, ny)[1])
            elif feature in BRIDGE_FEATURES:
                below = set().union(*support_cells[:-1])
                longest_bridge = max(longest_bridge, _unsupported_run(x, y, nx, ny, below))
        x, y = nx, ny

    total = sum(extruded.values()) or 1.0

    def pct(names: set[str]) -> float:
        return round(100 * sum(v for k, v in extruded.items() if k in names) / total, 1)

    return {
        "layers": layers,
        "height_mm": round(max_z, 2),
        "supports": any(extruded.get(f, 0) > 0 for f in SUPPORT_FEATURES),
        "support_pct": pct(SUPPORT_FEATURES),
        "overhang_wall_pct": pct({"Overhang wall"}),
        "bridge_pct": pct(BRIDGE_FEATURES),
        "max_bridge_mm": round(longest_bridge, 1),
        "features": sorted(k for k, v in extruded.items() if v > 0),
    }


def threemf_metrics(threemf: Path) -> dict:
    """Everything above for one sliced plate, rounded for stable snapshots."""
    info = slice_info(threemf)
    with zipfile.ZipFile(threemf) as z:
        gcode = z.read(PLATE_GCODE).decode(errors="replace")
    metrics = {
        **info,
        "time_s": int(info["time_s"]) if info["time_s"] is not None else None,
        "filament_g": round(info["filament_g"], 1) if info["filament_g"] is not None else None,
        **gcode_metrics(gcode),
    }
    return metrics
