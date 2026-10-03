"""Shared fixtures for the scad-tools test suite."""

import shutil
from pathlib import Path

import pytest
from click.testing import CliRunner

# Tests that shell out to a real OpenSCAD; skipped where none is installed
requires_openscad = pytest.mark.skipif(
    shutil.which("openscad") is None, reason="OpenSCAD not on PATH"
)


@pytest.fixture
def runner() -> CliRunner:
    return CliRunner()


@pytest.fixture
def write(tmp_path: Path):
    """Write a file under tmp_path (creating parent dirs) and return its path."""

    def _write(rel: str, content: str) -> Path:
        path = tmp_path / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    return _write


@pytest.fixture
def fake_openscad(tmp_path: Path):
    """
    Build a stand-in OpenSCAD: a shell script whose body runs with $out set to
    the -o argument. `--help` and `--version` exit 0 with no output.
    """

    def _make(body: str) -> str:
        script = tmp_path / "fake-openscad"
        script.write_text(
            "#!/bin/sh\n"
            'case "$1" in --help|--version) exit 0 ;; esac\n'
            "out=\n"
            'while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done\n'
            f"{body}\n"
        )
        script.chmod(0o755)
        return str(script)

    return _make
