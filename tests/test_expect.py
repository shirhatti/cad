"""Per-model print expectations from pyproject.toml."""

import click
import pytest

from scripts.expect import evaluate, expectations_for, format_duration, load_expectations, parse_duration


@pytest.mark.parametrize("value, seconds", [(90, 90), ("90m", 5400), ("1h30m", 5400), ("1h 30m 10s", 5410), ("1.5h", 5400)])
def test_parse_duration(value, seconds):
    assert parse_duration(value) == seconds


@pytest.mark.parametrize("value", ["soon", "1x", "", True])
def test_parse_duration_rejects(value):
    with pytest.raises(ValueError):
        parse_duration(value)


def test_format_duration():
    assert (format_duration(754), format_duration(7382)) == ("12m34s", "2h03m")


def test_load_and_merge(tmp_path, write, capsys):
    write("projects/p/a.scad", "")
    pyproject = write("pyproject.toml", """
[tool.scad-tools.expect.defaults]
bodies = 1
max_bridge_mm = 25
[tool.scad-tools.expect.models."p/a.scad"]
bodies = 2
max_time = "1h"
[tool.scad-tools.expect.models."p/gone.scad"]
supports = false
""")
    defaults, models = load_expectations(tmp_path / "projects", pyproject)
    assert expectations_for("p/a.scad", defaults, models) == {"bodies": 2, "max_bridge_mm": 25.0, "max_time": 3600}
    assert expectations_for("p/other.scad", defaults, models) == {"bodies": 1, "max_bridge_mm": 25.0}
    assert "Expectations match no model" in capsys.readouterr().err


@pytest.mark.parametrize("body, match", [
    ('[tool.scad-tools.expect.defaults]\nmax_tme = "1h"', "unknown expectation 'max_tme'"),
    ('[tool.scad-tools.expect.defaults]\nbodies = "two"', "expected an integer"),
    ('[tool.scad-tools.expect.defaults]\nsupports = 0', "expected true/false"),
    ('[tool.scad-tools.expect.oops]\nx = 1', "unknown table"),
])
def test_bad_config_is_an_error(tmp_path, write, body, match):
    pyproject = write("pyproject.toml", body)
    with pytest.raises(click.ClickException, match=match):
        load_expectations(tmp_path, pyproject)


def test_evaluate_by_stage():
    expected = {"bodies": 1, "max_time": 3600, "supports": False, "min_wall_mm": 0.8, "max_bridge_mm": 25.0}
    mesh = {"bodies": 2, "min_wall_mm": 0.5}
    slice_ = {"time_s": 4000, "supports": False, "max_bridge_mm": None}
    assert evaluate("mesh", mesh, expected) == [
        "bodies: expected 1, got 2 (separate printed parts)",
        "min_wall_mm: 0.5 mm is under the minimum of 0.8 mm (thinnest 1% of walls)",
    ]
    assert evaluate("slice", slice_, expected) == [
        "max_time: 1h06m is over the budget of 1h00m (predicted print time)",
        "max_bridge_mm: no max_bridge_mm measured, can't check 25 mm",
    ]
