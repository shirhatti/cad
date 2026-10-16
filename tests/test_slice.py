"""`scad-tools slice` preflight, OrcaSlicer version detection, and `profiles fetch`."""

import subprocess
from pathlib import Path

import pytest

from scripts import scad_tools
from scripts.scad_tools import cli, compute_profiles_hash, get_orca_version


@pytest.fixture(autouse=True)
def fresh_caches():
    get_orca_version.cache_clear()
    scad_tools.orca_profiles_commit.cache_clear()
    yield
    get_orca_version.cache_clear()
    scad_tools.orca_profiles_commit.cache_clear()


def git(*args, cwd):
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=cwd, check=True, capture_output=True,
    )


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


def make_repo_with_pin(tmp_path: Path) -> tuple[Path, Path, str]:
    """An upstream repo with profiles + other files, and a parent pinning it."""
    upstream = tmp_path / "upstream"
    (upstream / "resources/profiles/BBL").mkdir(parents=True)
    (upstream / "resources/profiles/BBL/x.json").write_text("{}")
    (upstream / "src").mkdir()
    (upstream / "src/big.cpp").write_text("int main;")
    git("init", "-q", cwd=upstream)
    git("add", ".", cwd=upstream)
    git("commit", "-qm", "upstream", cwd=upstream)
    # Let a file:// fetch ask for a bare sha with a filter, as GitHub allows
    git("config", "uploadpack.allowFilter", "true", cwd=upstream)
    git("config", "uploadpack.allowAnySHA1InWant", "true", cwd=upstream)
    sha = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=upstream, capture_output=True, text=True, check=True
    ).stdout.strip()

    parent = tmp_path / "parent"
    (parent / "projects").mkdir(parents=True)  # the CLI's default --base-path
    git("init", "-q", cwd=parent)
    git("update-index", "--add", "--cacheinfo", f"160000,{sha},.orca-slicer", cwd=parent)
    git("commit", "-qm", "pin", cwd=parent)
    return upstream, parent, sha


def test_profiles_fetch_is_sparse_and_idempotent(runner, tmp_path, monkeypatch):
    upstream, parent, sha = make_repo_with_pin(tmp_path)
    monkeypatch.chdir(parent)
    remote = f"file://{upstream}"

    result = runner.invoke(cli, ["profiles", "fetch", "--remote", remote])
    assert result.exit_code == 0, result.output
    assert (parent / ".orca-slicer/resources/profiles/BBL/x.json").is_file()
    assert not (parent / ".orca-slicer/src").exists()

    result = runner.invoke(cli, ["profiles", "fetch", "--remote", remote])
    assert result.exit_code == 0, result.output
    assert "already at" in result.output


def test_profiles_hash_tracks_upstream_pin(tmp_path, monkeypatch):
    _, parent, _ = make_repo_with_pin(tmp_path)
    monkeypatch.chdir(parent)
    pinned = compute_profiles_hash()

    git("update-index", "--cacheinfo", f"160000,{'1' * 40},.orca-slicer", cwd=parent)
    git("commit", "-qm", "bump", cwd=parent)
    scad_tools.orca_profiles_commit.cache_clear()
    assert compute_profiles_hash() != pinned


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
