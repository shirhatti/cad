"""`scad-tools render`: STL failures fail the run; a bad preview only warns."""

import pytest
from conftest import requires_openscad

from scripts.scad_tools import cli

OUT_NAME = "proj__model"


@pytest.fixture(autouse=True)
def no_cache(monkeypatch):
    monkeypatch.delenv("GITHUB_REPOSITORY", raising=False)


def render(runner, tmp_path, *args):
    return runner.invoke(
        cli,
        ["--base-path", str(tmp_path / "projects"), "render",
         "--output-dir", str(tmp_path / "artifacts"), "-j", "1", *args],
    )


@pytest.mark.parametrize(
    "png_step",
    [
        ': > "$out"',  # empty PNG, exit 0 (OpenSCAD 2021 without a display)
        "exit 0",  # no PNG at all, exit 0
        'echo junk > "$out"; exit 1',  # partial PNG, non-zero exit
    ],
    ids=["empty", "missing", "failed"],
)
def test_bad_preview_is_deleted_and_warned(runner, tmp_path, write, fake_openscad, png_step):
    write("projects/proj/model.scad", "cube(1);\n")
    openscad = fake_openscad(
        f'case "$out" in *.stl) echo "solid x" > "$out" ;; *.png) {png_step} ;; esac'
    )
    result = render(runner, tmp_path, "--openscad", openscad)
    assert result.exit_code == 0, result.output
    assert "Preview render produced no image" in result.output
    assert (tmp_path / f"artifacts/stl/{OUT_NAME}.stl").exists()
    assert not (tmp_path / f"artifacts/preview/{OUT_NAME}.png").exists()


def test_stl_failure_fails_render(runner, tmp_path, write, fake_openscad):
    write("projects/proj/model.scad", "cube(1);\n")
    openscad = fake_openscad('echo "ERROR: boom" >&2; exit 1')
    result = render(runner, tmp_path, "--openscad", openscad)
    assert result.exit_code == 1, result.output
    assert "STL render failed" in result.output


@requires_openscad
def test_real_render_writes_stl_and_preview(runner, tmp_path, write):
    write("projects/proj/model.scad", "cube(1);\n")
    result = render(runner, tmp_path)
    assert result.exit_code == 0, result.output
    assert (tmp_path / f"artifacts/stl/{OUT_NAME}.stl").stat().st_size > 0
    assert (tmp_path / f"artifacts/preview/{OUT_NAME}.png").stat().st_size > 0
