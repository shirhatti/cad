"""Print-metrics snapshot: collect, tolerance, diff, check."""

import json

from scripts.scad_tools import cli
from scripts.snapshot import collect, diff_rows, markdown_report, same, stabilize


def write_metrics(dir_, model, stage, data):
    dir_.mkdir(parents=True, exist_ok=True)
    (dir_ / f"{model}.{stage}.json").write_text(json.dumps(data))


def test_collect_keys_by_model_path(tmp_path):
    write_metrics(tmp_path, "rack__bracket", "mesh", {"bodies": 1})
    write_metrics(tmp_path, "rack__bracket", "slice", {"time_s": 60})
    write_metrics(tmp_path, "test__cube", "mesh", {"bodies": 1})
    assert collect(tmp_path) == {
        "rack/bracket.scad": {"mesh": {"bodies": 1}, "slice": {"time_s": 60}},
        "test/cube.scad": {"mesh": {"bodies": 1}},
    }


def test_estimates_compare_within_tolerance():
    assert same("time_s", 16887, 16885)  # seconds of jitter
    assert same("time_s", 10000, 10150)  # within 2%
    assert not same("time_s", 10000, 11000)
    assert not same("layers", 190, 191)  # exact metrics stay exact


def test_stabilize_keeps_committed_values_within_tolerance():
    before = {"m": {"slice": {"time_s": 16887, "layers": 190}}}
    current = {"m": {"slice": {"time_s": 16885, "layers": 191}}}
    assert stabilize(before, current) == {"m": {"slice": {"time_s": 16887, "layers": 191}}}


def test_markdown_report():
    before = {"a.scad": {"slice": {"time_s": 3600, "supports": False, "features": ["Outer wall"]}}}
    after = {
        "a.scad": {"slice": {"time_s": 4500, "supports": True, "features": ["Outer wall", "Support"]}},
        "b.scad": {"mesh": {"bodies": 1}},
    }
    rows = diff_rows(before, after)
    assert ("a.scad", "slice: print time", "1h00m", "1h15m", "+25%") in rows
    assert ("a.scad", "slice: supports", "no", "yes", "") in rows
    assert ("a.scad", "slice: features", "Outer wall", "Outer wall, Support", "+Support") in rows
    assert ("b.scad", "model", "—", "new", "") in rows
    report = markdown_report(before, after)
    assert "2 of 2 model(s) changed." in report
    assert markdown_report(after, after).endswith("No print-metric changes across 2 model(s).\n")


def test_check_and_snapshot_commands(runner, tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "projects").mkdir()
    metrics_dir = tmp_path / "artifacts/metrics"
    write_metrics(metrics_dir, "p__m", "slice", {"time_s": 3600})

    result = runner.invoke(cli, ["metrics", "check"])
    assert result.exit_code == 1 and "out of date" in result.output

    result = runner.invoke(cli, ["metrics", "snapshot"])
    assert result.exit_code == 0, result.output
    assert json.loads((tmp_path / "print-metrics.json").read_text()) == {"p/m.scad": {"slice": {"time_s": 3600}}}

    write_metrics(metrics_dir, "p__m", "slice", {"time_s": 3610})  # jitter
    assert runner.invoke(cli, ["metrics", "check"]).exit_code == 0

    result = runner.invoke(cli, ["metrics", "diff", "print-metrics.json"])
    assert "No print-metric changes" in result.output
