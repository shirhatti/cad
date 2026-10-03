"""Customizer linting via `scad-tools lint` and the customizer-lint entry point."""

import sys

import pytest

from scripts import customizer_lint
from scripts.scad_tools import cli

# Fully annotated parameter: no errors, no warnings
CLEAN = "/* [Size] */\n// Edge length\nsize = 10; // [5:1:50]\ncube(size);\n"
# Valid, but the parameter lacks a description comment: a warning only
WARNING_ONLY = "/* [Size] */\nsize = 10; // [5:1:50]\ncube(size);\n"
# No Customizer parameters at all: an error
NOT_CUSTOMIZABLE = "cube(1);\n"


def lint(runner, tmp_path, *args):
    return runner.invoke(cli, ["--base-path", str(tmp_path), "lint", *args])


def test_lint_clean_file_passes_strict(runner, tmp_path, write):
    write("proj/model.scad", CLEAN)
    result = lint(runner, tmp_path, "--strict")
    assert result.exit_code == 0, result.output


def test_lint_warnings_pass_by_default(runner, tmp_path, write):
    write("proj/model.scad", WARNING_ONLY)
    result = lint(runner, tmp_path)
    assert result.exit_code == 0, result.output
    assert "lacks a description" in result.output


def test_lint_strict_quiet_fails_on_warnings_only(runner, tmp_path, write):
    write("proj/model.scad", WARNING_ONLY)
    result = lint(runner, tmp_path, "--strict", "--quiet")
    assert result.exit_code == 1, result.output
    assert "lacks a description" not in result.output  # quiet hides warnings
    assert "1 file(s) failed" in result.output


def test_lint_fails_on_errors(runner, tmp_path, write):
    write("proj/model.scad", NOT_CUSTOMIZABLE)
    result = lint(runner, tmp_path)
    assert result.exit_code == 1, result.output


def test_lint_skips_non_model_files(runner, tmp_path, write):
    write("proj/model.scad", CLEAN)
    write("proj/model_test.scad", NOT_CUSTOMIZABLE)
    write("proj/model_lib.scad", NOT_CUSTOMIZABLE)
    result = lint(runner, tmp_path, "--strict")
    assert result.exit_code == 0, result.output


def run_main(monkeypatch, *args):
    monkeypatch.setattr(sys, "argv", ["customizer-lint", "--no-color", *map(str, args)])
    return customizer_lint.main()


@pytest.mark.parametrize("name", ["foo_test.scad", "foo_lib.scad", "foo_constants.scad", "foo_reference.scad"])
def test_main_skips_explicitly_passed_excluded_file(monkeypatch, capsys, write, name):
    # pre-commit passes every changed .scad file, including tests and libs
    path = write(name, NOT_CUSTOMIZABLE)
    assert run_main(monkeypatch, path) == 0
    assert "No Customizer parameters" not in capsys.readouterr().out


def test_main_lints_explicitly_passed_model(monkeypatch, capsys, write):
    path = write("foo.scad", NOT_CUSTOMIZABLE)
    assert run_main(monkeypatch, path) == 1
    assert "No Customizer parameters" in capsys.readouterr().out


def test_main_strict_quiet_fails_on_warnings_only(monkeypatch, write):
    path = write("foo.scad", WARNING_ONLY)
    assert run_main(monkeypatch, path) == 0
    assert run_main(monkeypatch, "--strict", "--quiet", path) == 1


def test_main_rejects_missing_path(monkeypatch, tmp_path):
    assert run_main(monkeypatch, tmp_path / "nope.scad") == 1
