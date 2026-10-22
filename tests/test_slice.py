"""`scad-tools slice`: preflight, OrcaSlicer version detection, exclusions, post-slice checks."""

import json
from pathlib import Path

import pytest
from test_slice_metrics import make_3mf

from scripts import profiles, scad_tools
from scripts.scad_tools import cli, get_orca_version


@pytest.fixture(autouse=True)
def fresh_caches():
    get_orca_version.cache_clear()
    yield
    get_orca_version.cache_clear()


def fake_bin(tmp_path: Path, name: str, body: str) -> str:
    script = tmp_path / "bin" / name
    script.parent.mkdir(exist_ok=True)
    script.write_text(f"#!/bin/sh\n{body}\n")
    script.chmod(0o755)
    return str(script)


@pytest.mark.parametrize(
    "banner, version",
    [
        # 2.3.1's --help: trace noise on stderr, banner, then help text with
        # other dotted lines that the old "any line with v and ." heuristic hit
        ("echo '[trace] Initializing StaticPrintConfigs' >&2\n"
         "echo 'OrcaSlicer-2.3.1:'\necho 'Allow 3mf with newer version to be sliced.'", "2.3.1"),
        ("echo 'OrcaSlicer v2.4.0-beta: usage'", "2.4.0-beta"),
        ("echo 'no banner here v1.2'", "unknown"),
    ],
)
def test_orca_version_parses_banner(tmp_path, banner, version):
    assert get_orca_version(fake_bin(tmp_path, "orca", banner)) == version


def test_slice_fails_fast_without_profiles(runner, tmp_path, monkeypatch, write):
    write("projects/proj/model.scad", "cube(1);\n")
    write("artifacts/stl/proj__model.stl", "solid x\n")
    orca = fake_bin(tmp_path, "orca-slicer", "echo should-not-run; exit 1")
    monkeypatch.setenv("PATH", f"{Path(orca).parent}:/usr/bin:/bin")
    monkeypatch.chdir(tmp_path)

    result = runner.invoke(cli, ["slice"])
    assert result.exit_code == 1, result.output
    assert "Slicer profile(s) not found" in result.output
    assert "scad-tools profiles fetch" in result.output
    assert "should-not-run" not in result.output


def test_slice_exclusions(tmp_path, monkeypatch, write, capsys):
    write("projects/proj/big.scad", "cube(1);\n")
    write(
        "pyproject.toml",
        '[tool.scad-tools.slice.exclude]\n"proj/big.scad" = "too big"\n"proj/gone.scad" = "renamed"\n',
    )
    monkeypatch.chdir(tmp_path)
    exclusions = scad_tools.get_slice_exclusions(Path("projects"))
    assert exclusions == {"proj__big": "too big", "proj__gone": "renamed"}
    assert "matches no model: projects/proj/gone.scad" in capsys.readouterr().err

    write("pyproject.toml", "[tool.scad-tools.slice.exclude\n")
    with pytest.raises(scad_tools.click.ClickException, match="Can't read slice exclusions"):
        scad_tools.get_slice_exclusions(Path("projects"))


def setup_slice_project(tmp_path, monkeypatch, effective_overrides=None, expect=""):
    """
    A project with one rendered model, minimal profiles, and a fake OrcaSlicer
    that records its arguments and "exports" a 3MF whose project settings are
    the flattened profiles (plus effective_overrides, to simulate the slicer
    ignoring something).
    """
    monkeypatch.chdir(tmp_path)
    monkeypatch.delenv("GITHUB_REPOSITORY", raising=False)
    up = Path(".orca-slicer/resources/profiles/BBL")
    local = Path(".orca-profiles-local/BBL")
    files = {
        local / "machine/Bambu Lab A1 0.4 nozzle.json": {"type": "machine", "name": "Bambu Lab A1 0.4 nozzle",
                                                         "printable_area": ["0x0", "256x0", "256x256", "0x256"],
                                                         "printable_height": "256"},
        local / "process/0.20mm Standard @BBL A1.json": {"type": "process", "name": "0.20mm Standard @BBL A1",
                                                         "layer_height": "0.2", "enable_support": "1"},
        up / "filament/fdm_filament_pla.json": {"type": "filament", "name": "fdm_filament_pla",
                                                "filament_density": ["1.24"]},
        up / "filament/Generic PLA @BBL A1.json": {"type": "filament", "name": "Generic PLA @BBL A1",
                                                   "inherits": "fdm_filament_pla"},
    }
    for path, data in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data))
    profiles.upstream_index.cache_clear()

    effective = {"printable_area": ["0x0", "256x0", "256x256", "0x256"], "printable_height": "256",
                 "layer_height": "0.2", "enable_support": "1", "filament_density": ["1.24"],
                 **(effective_overrides or {})}
    gcode = "M83\n; CHANGE_LAYER\n; Z_HEIGHT: 0.2\n; FEATURE: Outer wall\nG1 X1 E1\n"
    canned = make_3mf(tmp_path / "canned.3mf", gcode, effective, time=3600, weight="10")

    write_model = tmp_path / "projects/proj/model.scad"
    write_model.parent.mkdir(parents=True)
    write_model.write_text("cube(1);\n")
    (tmp_path / "artifacts/stl").mkdir(parents=True)
    (tmp_path / "artifacts/stl/proj__model.stl").write_text("solid x\n")
    (tmp_path / "pyproject.toml").write_text(expect)

    args_log = tmp_path / "orca-args"
    orca = fake_bin(tmp_path, "orca-slicer", f"""
case "$1" in --help) echo 'OrcaSlicer-2.3.1:'; exit 0 ;; esac
printf '%s\\n' "$@" > {args_log}
while [ $# -gt 0 ]; do [ "$1" = --export-3mf ] && cp {canned} "$2"; shift; done
""")
    monkeypatch.setenv("PATH", f"{Path(orca).parent}:/usr/bin:/bin")
    return args_log


def test_slice_passes_flattened_profiles_and_writes_metrics(runner, tmp_path, monkeypatch):
    args_log = setup_slice_project(tmp_path, monkeypatch)
    result = runner.invoke(cli, ["slice", "-j", "1"])
    assert result.exit_code == 0, result.output

    args = args_log.read_text().splitlines()
    flat = tmp_path / "artifacts/profiles"
    # Filament goes through its own flag, as a flattened (inherits-free) file
    assert args[args.index("--load-settings") + 1] == f"{flat / 'machine.json'};{flat / 'process.json'}"
    assert args[args.index("--load-filaments") + 1] == str(flat / "filament.json")
    assert json.loads((flat / "filament.json").read_text())["filament_density"] == ["1.24"]

    metrics = json.loads((tmp_path / "artifacts/metrics/proj__model.slice.json").read_text())
    assert (metrics["time_s"], metrics["filament_g"]) == (3600, 10.0)


def test_slice_fails_when_slicer_ignores_a_setting(runner, tmp_path, monkeypatch):
    setup_slice_project(tmp_path, monkeypatch, {"filament_density": ["0"]})
    result = runner.invoke(cli, ["slice", "-j", "1"])
    assert result.exit_code == 1, result.output
    assert "filament.filament_density: profile has ['1.24'], slicer used ['0']" in result.output


def test_slice_fails_over_budget(runner, tmp_path, monkeypatch):
    setup_slice_project(tmp_path, monkeypatch, expect='[tool.scad-tools.expect.models."proj/model.scad"]\nmax_time = "45m"\n')
    result = runner.invoke(cli, ["slice", "-j", "1"])
    assert result.exit_code == 1, result.output
    assert "max_time: 1h00m is over the budget of 45m00s" in result.output


SETTINGS = '[tool.scad-tools.slice.settings."proj/model.scad"]\nenable_support = false\n'


def test_slice_applies_per_model_settings(runner, tmp_path, monkeypatch):
    args_log = setup_slice_project(tmp_path, monkeypatch, {"enable_support": "0"}, expect=SETTINGS)
    result = runner.invoke(cli, ["slice", "-j", "1"])
    assert result.exit_code == 0, result.output
    assert "overrides: enable_support=0" in result.output

    # The model gets its own profile set with the override applied
    own = tmp_path / "artifacts/profiles/proj__model"
    args = args_log.read_text().splitlines()
    assert args[args.index("--load-settings") + 1] == f"{own / 'machine.json'};{own / 'process.json'}"
    assert json.loads((own / "process.json").read_text())["enable_support"] == "0"
    assert json.loads((tmp_path / "artifacts/profiles/process.json").read_text())["enable_support"] == "1"
    metrics = json.loads((tmp_path / "artifacts/metrics/proj__model.slice.json").read_text())
    assert metrics["settings"] == {"enable_support": "0"}


def test_slice_fails_when_slicer_ignores_a_model_setting(runner, tmp_path, monkeypatch):
    setup_slice_project(tmp_path, monkeypatch, expect=SETTINGS)  # 3MF still says enable_support=1
    result = runner.invoke(cli, ["slice", "-j", "1"])
    assert result.exit_code == 1, result.output
    assert "process.enable_support: profile has '0', slicer used '1'" in result.output
