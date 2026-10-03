"""File classification (EXCLUDE_SUFFIXES) and include-dependency discovery."""

from pathlib import Path

import pytest

from scripts.scad_tools import find_scad_dependencies, find_scad_files, is_model_file


@pytest.mark.parametrize(
    "name, expected",
    [
        ("bracket.scad", True),
        ("bracket_test.scad", False),
        ("bracket_lib.scad", False),
        ("shelf_constants.scad", False),
        ("shelf_reference.scad", False),
        ("test_cube.scad", True),  # only suffixes count
        ("bracket.stl", False),
    ],
)
def test_is_model_file(name, expected):
    assert is_model_file(Path(name)) is expected


@pytest.fixture
def project(write):
    for name in ("model", "a_test", "b_lib", "c_constants", "d_reference"):
        write(f"proj/{name}.scad", "")
    return lambda files: sorted(f.name for f in files)


def test_find_scad_files_default_is_models_only(tmp_path, project):
    assert project(find_scad_files(tmp_path)) == ["model.scad"]


def test_find_scad_files_only_tests(tmp_path, project):
    assert project(find_scad_files(tmp_path, only_tests=True)) == ["a_test.scad"]


def test_find_scad_files_include_flags(tmp_path, project):
    assert project(find_scad_files(tmp_path, include_libs=True)) == ["b_lib.scad", "model.scad"]
    everything = find_scad_files(
        tmp_path,
        include_tests=True,
        include_libs=True,
        include_constants=True,
        include_reference=True,
    )
    assert len(everything) == 5


def test_dependencies_terminate_on_cycle(write):
    a = write("a.scad", "include <b.scad>\n")
    b = write("b.scad", "include <a.scad>\n")
    assert find_scad_dependencies(a) == [b.resolve()]


def test_dependencies_ignore_commented_out_includes(write):
    a = write(
        "a.scad",
        "// include <line.scad>\n"
        "/* include <block.scad>\n   use <block2.scad> */\n"
        "use <real.scad>\n",
    )
    for name in ("line", "block", "block2", "real"):
        write(f"{name}.scad", "")
    assert [d.name for d in find_scad_dependencies(a)] == ["real.scad"]


def test_dependencies_resolve_relative_to_including_file(write):
    a = write("a.scad", "include <sub/b.scad>\n")
    write("sub/b.scad", "include <c.scad>\n")
    nested = write("sub/c.scad", "")
    write("c.scad", "")  # decoy next to a.scad; must not be picked
    deps = find_scad_dependencies(a)
    assert nested.resolve() in deps
    assert [d.relative_to(a.parent.resolve()).as_posix() for d in deps] == ["sub/b.scad", "sub/c.scad"]


def test_dependencies_skip_missing_files(write):
    a = write("a.scad", "include <missing.scad>\n")
    assert find_scad_dependencies(a) == []
