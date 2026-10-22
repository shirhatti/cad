"""Metrics read back from a sliced 3MF and its G-code."""

import json
import zipfile
from pathlib import Path

from scripts.slice_metrics import gcode_metrics, threemf_metrics

SLICE_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<config><plate>
  <metadata key="prediction" value="{time}"/>
  <metadata key="weight" value="{weight}"/>
  <metadata key="outside" value="false"/>
  <metadata key="support_used" value="true"/>
  <filament id="1" type="PLA" used_m="1.50" used_g="{weight}"/>
</plate></config>
"""


def make_3mf(path: Path, gcode: str, settings: dict | None = None, time: int = 600, weight: str = "2.5") -> Path:
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("Metadata/slice_info.config", SLICE_INFO.format(time=time, weight=weight))
        z.writestr("Metadata/project_settings.config", json.dumps(settings or {}))
        z.writestr("Metadata/plate_1.gcode", gcode)
    return path


def layer(z: float, *body: str) -> str:
    return "\n".join(["; CHANGE_LAYER", f"; Z_HEIGHT: {z}", *body])


# A 30 mm bridge line from (0,0) to (30,0)
BRIDGE = ["; FEATURE: Bridge", "G1 X0 Y0", "G1 X30 Y0 E1.5"]


def test_feature_shares_and_layers():
    gcode = "\n".join([
        "M83",
        layer(0.2, "; FEATURE: Outer wall", "G1 X10 Y0 E3", "G1 E-0.8", "; FEATURE: Support", "G1 X20 Y0 E1"),
        layer(0.4, "; FEATURE: Overhang wall", "G1 X20 Y10 E1"),
    ])
    m = gcode_metrics(gcode)
    assert (m["layers"], m["height_mm"]) == (2, 0.4)
    # Retraction (E-0.8) doesn't count: 3 + 1 + 1 = 5 total
    assert (m["support_pct"], m["overhang_wall_pct"], m["supports"]) == (20.0, 20.0, True)
    assert m["features"] == ["Outer wall", "Overhang wall", "Support"]


def test_absolute_extrusion_mode():
    m = gcode_metrics("\n".join(["M82", layer(0.2, "; FEATURE: Outer wall", "G1 X1 E2", "G1 X2 E5", "G92 E0", "; FEATURE: Support", "G1 X3 E5")]))
    assert m["support_pct"] == 50.0  # 5 of 10 mm of filament


def test_bridge_over_air_counts_the_span():
    # Anchored only at x=0..1 below; the rest of the 30 mm line is over air,
    # less the 1-2 mm anchoring tolerance
    m = gcode_metrics("\n".join(["M83", layer(0.2, "; FEATURE: Outer wall", "G1 X1 E1"), layer(0.4, *BRIDGE)]))
    assert 27 <= m["max_bridge_mm"] <= 29
    assert m["supports"] is False


def test_bridge_along_a_narrow_channel_is_not_a_span():
    # The roof of a 2 mm channel: walls 2 mm apart below, a bridge line running
    # lengthwise between them. Long line, trivial span.
    walls = ["; FEATURE: Inner wall", "G1 X0 Y-1", "G1 X30 Y-1 E1", "G1 X30 Y1", "G1 X0 Y1 E1"]
    m = gcode_metrics("\n".join(["M83", layer(0.2, *walls), layer(0.4, *BRIDGE)]))
    assert m["max_bridge_mm"] == 0.0


def test_bridge_over_support_is_not_a_span():
    support_under = ["; FEATURE: Support interface", "G1 X0 Y0", "G1 X30 Y0 E1"]
    m = gcode_metrics("\n".join(["M83", layer(0.2, *support_under), layer(0.4, *BRIDGE)]))
    assert m["max_bridge_mm"] == 0.0


def test_bridge_partly_over_support_measures_the_air_gap():
    support_under = ["; FEATURE: Support", "G1 X0 Y0", "G1 X10 Y0 E1"]  # only the first 10 mm
    m = gcode_metrics("\n".join(["M83", layer(0.2, *support_under), layer(0.4, *BRIDGE)]))
    # Support cells cover x < 10 plus one 2 mm neighbor cell of tolerance
    assert 15 <= m["max_bridge_mm"] <= 20


def test_threemf_metrics(tmp_path):
    threemf = make_3mf(tmp_path / "x.3mf", "\n".join(["M83", layer(0.2, "; FEATURE: Outer wall", "G1 X1 E1")]), time=754, weight="12.34")
    m = threemf_metrics(threemf)
    assert (m["time_s"], m["filament_g"], m["filament_m"], m["fits_plate"]) == (754, 12.3, 1.5, True)
    # support_used="true" in slice_info only means support is enabled
    assert m["supports"] is False


def test_missing_weight_is_none(tmp_path):
    threemf = make_3mf(tmp_path / "x.3mf", "M83\n", weight="")
    assert threemf_metrics(threemf)["filament_g"] is None
