"""Pinned toolchain helpers (`scad-tools toolchain ...`)."""

import shutil
from pathlib import Path

import pytest

from scripts import toolchain
from scripts.scad_tools import cli

REPO = Path(__file__).resolve().parent.parent


@pytest.fixture
def repo_copy(tmp_path, monkeypatch):
    """A tmp dir holding copies of toolchain.toml and ci/Dockerfile, as cwd."""
    (tmp_path / "ci").mkdir()
    shutil.copy(REPO / "toolchain.toml", tmp_path / "toolchain.toml")
    shutil.copy(REPO / "ci/Dockerfile", tmp_path / "ci/Dockerfile")
    monkeypatch.chdir(tmp_path)
    return tmp_path


def image_ref() -> str:
    return toolchain.ci_image_ref(toolchain.load_toolchain())


def test_ci_image_ref_is_deterministic(repo_copy):
    ref = image_ref()
    assert ref == image_ref()
    assert ref.startswith(toolchain.load_toolchain()["mirror"] + "/ci:")


@pytest.mark.parametrize("path", ["toolchain.toml", "ci/Dockerfile"])
def test_ci_image_ref_tracks_file_content(repo_copy, path):
    before = image_ref()
    with open(repo_copy / path, "a") as f:
        f.write("\n# changed\n")
    assert image_ref() != before


def test_image_ref_command(runner, repo_copy):
    result = runner.invoke(cli, ["--base-path", ".", "toolchain", "image-ref"])
    assert result.exit_code == 0, result.output
    assert result.output.strip() == image_ref()


def test_install_rejects_unknown_tool(runner, repo_copy):
    result = runner.invoke(
        cli,
        ["--base-path", ".", "toolchain", "install", "openscad", "bogus",
         "--prefix", str(repo_copy / "prefix")],
    )
    assert result.exit_code == 1
    assert "Unknown tool(s): bogus" in result.output
    assert not (repo_copy / "prefix").exists()  # nothing installed
