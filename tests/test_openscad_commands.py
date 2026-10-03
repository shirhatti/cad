"""`scad-tools test` and `check`: failures must be detected from OpenSCAD's output,
since OpenSCAD exits 0 on failed assert()s and most errors."""

import subprocess

import pytest
from conftest import requires_openscad

from scripts.scad_tools import cli, openscad_diagnostics


def run(runner, tmp_path, *args):
    return runner.invoke(cli, ["--base-path", str(tmp_path), *args, "-j", "1"])


@pytest.mark.parametrize("stream", ["stdout", "stderr"])
def test_diagnostics_read_both_streams(stream):
    result = subprocess.CompletedProcess([], 0, stdout="", stderr="")
    setattr(result, stream, "ECHO: 1\nERROR: Assertion failed\n")
    assert openscad_diagnostics(result, ("ERROR:",)) == ["ERROR: Assertion failed"]


@pytest.mark.parametrize("stream", ["1", "2"])
def test_test_fails_on_error_with_exit_zero(runner, tmp_path, write, fake_openscad, stream):
    # A fake OpenSCAD that reports a failed assert on either stream but exits 0
    openscad = fake_openscad(f'echo "ERROR: Assertion \'false\' failed" >&{stream}; exit 0')
    write("proj/a_test.scad", "")
    result = run(runner, tmp_path, "test", "--openscad", openscad)
    assert result.exit_code == 1, result.output
    assert "FAILED" in result.output


@requires_openscad
def test_test_fails_on_failed_assert(runner, tmp_path, write):
    write("proj/a_test.scad", 'assert(1 == 2, "x");\n')
    result = run(runner, tmp_path, "test")
    assert result.exit_code == 1, result.output
    assert "Assertion" in result.output
    assert "PASSED" not in result.output


@requires_openscad
def test_test_passes_on_passing_assert(runner, tmp_path, write):
    write("proj/a_test.scad", 'assert(1 == 1, "x");\necho("ok");\n')
    result = run(runner, tmp_path, "test")
    assert result.exit_code == 0, result.output
    assert "PASSED" in result.output
    assert 'ECHO: "ok"' in result.output


@requires_openscad
def test_test_fails_on_warning(runner, tmp_path, write):
    write("proj/a_test.scad", "echo(undefined_variable);\n")
    result = run(runner, tmp_path, "test")
    assert result.exit_code == 1, result.output
    assert "WARNING:" in result.output


@requires_openscad
def test_test_only_runs_test_files(runner, tmp_path, write):
    write("proj/broken.scad", 'assert(false, "not a test");\n')
    write("proj/ok_test.scad", "assert(true);\n")
    result = run(runner, tmp_path, "test")
    assert result.exit_code == 0, result.output
    assert "broken.scad" not in result.output


@requires_openscad
def test_check_fails_on_error(runner, tmp_path, write):
    write("proj/model.scad", 'assert(1 == 2, "x");\ncube(1);\n')
    result = run(runner, tmp_path, "check")
    assert result.exit_code == 1, result.output
    assert "ERROR:" in result.output


@requires_openscad
def test_check_passes_on_valid_model(runner, tmp_path, write):
    write("proj/model.scad", "cube(1);\n")
    result = run(runner, tmp_path, "check")
    assert result.exit_code == 0, result.output
    assert "validated successfully" in result.output
