"""Profile flattening, verification, lint, and `profiles fetch`."""

import json
import subprocess
from pathlib import Path

import click
import pytest

from scripts import profiles as P
from scripts.scad_tools import cli, compute_profiles_hash

UP = Path(".orca-slicer/resources/profiles/BBL")
LOCAL = Path(".orca-profiles-local/BBL")


@pytest.fixture(autouse=True)
def fresh_caches():
    for fn in (P.upstream_index, P.known_keys, P.orca_profiles_commit):
        fn.cache_clear()
    yield
    for fn in (P.upstream_index, P.known_keys, P.orca_profiles_commit):
        fn.cache_clear()


def put(path: Path, data: dict) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))
    return path


@pytest.fixture
def tree(tmp_path, monkeypatch):
    """A tiny upstream vendor dir (machine chain + filament chain) in cwd."""
    monkeypatch.chdir(tmp_path)
    put(UP / "machine/common.json", {"type": "machine", "name": "common", "printable_height": "100", "nozzle": "0.4"})
    put(UP / "machine/A1.json", {"type": "machine", "name": "A1", "inherits": "common", "printable_height": "256"})
    put(UP / "filament/pla.json", {"type": "filament", "name": "pla", "filament_density": ["1.24"], "nozzle_temperature": ["220"]})
    put(UP / "filament/PLA A1.json", {"type": "filament", "name": "PLA A1", "inherits": "pla", "nozzle_temperature": ["215"]})
    return tmp_path


def test_flatten_resolves_inherits_chain(tree):
    flat = P.flatten_profile("filament", UP / "filament/PLA A1.json")
    assert flat["filament_density"] == ["1.24"]  # inherited
    assert flat["nozzle_temperature"] == ["215"]  # leaf wins
    assert "inherits" not in flat


def test_local_override_layers_on_same_name_upstream(tree):
    local = put(LOCAL / "machine/A1.json", {"type": "machine", "name": "A1", "gcode": "G92 E0"})
    flat = P.flatten_profile("machine", local)
    # From the upstream A1 file and its parent, plus the local key
    assert (flat["printable_height"], flat["nozzle"], flat["gcode"]) == ("256", "0.4", "G92 E0")


def test_local_profile_with_inherits_builds_on_that_parent(tree):
    local = put(LOCAL / "machine/custom.json", {"type": "machine", "name": "custom", "inherits": "common"})
    assert P.flatten_profile("machine", local)["printable_height"] == "100"


def test_missing_parent_and_cycles_are_errors(tree):
    put(UP / "machine/x.json", {"type": "machine", "name": "x", "inherits": "y"})
    put(UP / "machine/y.json", {"type": "machine", "name": "y", "inherits": "x"})
    with pytest.raises(click.ClickException, match="cycle"):
        P.flatten_profile("machine", UP / "machine/x.json")
    bad = put(UP / "machine/z.json", {"type": "machine", "name": "z", "inherits": "nope"})
    with pytest.raises(click.ClickException, match="No upstream machine profile named 'nope'"):
        P.flatten_profile("machine", bad)


def test_verify_effective_settings():
    flat = {
        "machine": {"name": "A1", "printable_height": "256", "best_object_pos": "0.5x0.5",
                    "machine_max_acceleration_x": ["12000"], "my_override": "1", "newer_key": "1"},
        "filament": {"filament_density": ["1.24"], "top_shell_thickness": "1.0"},
    }
    effective = {
        "printable_height": "100",  # profile not applied
        "best_object_pos": "0.5,0.5",  # same value, different spelling
        "machine_max_acceleration_x": ["6000"],  # known CLI adjustment
        "filament_density": ["1.24"],
        "top_shell_thickness": "1",
    }
    errors, warnings = P.verify_effective_settings(flat, effective, {"machine": {"my_override"}})
    assert errors == [
        "machine.my_override is not a setting this slicer knows; ignored",
        "machine.printable_height: profile has '256', slicer used '100'",
    ]
    assert warnings == ["machine.newer_key is not a setting this slicer knows; ignored"]


def test_lint_flags_redundant_and_unknown_override_keys(tree):
    local = put(LOCAL / "machine/A1.json", {
        "type": "machine", "name": "A1",
        "printable_height": "256",  # same as inherited
        "nozzle": "0.6",  # a real override
        "nozle": "0.6",  # typo: no upstream profile uses it
    })
    errors, warnings = P.lint_profiles({"machine": local})
    assert errors == [f"{local}: unknown machine key 'nozle' (typo?)"]
    assert warnings == [f"{local}: printable_height = '256' is already the inherited value"]


def test_profiles_hash_tracks_flattened_content(tree):
    flat_dir = tree / "flat"
    profiles = {"filament": UP / "filament/PLA A1.json"}
    before = compute_profiles_hash(P.write_flat_profiles(flat_dir, profiles))
    # An upstream change deep in the chain changes the slicer input
    put(UP / "filament/pla.json", {"type": "filament", "name": "pla", "filament_density": ["1.30"]})
    P.upstream_index.cache_clear()
    assert compute_profiles_hash(P.write_flat_profiles(flat_dir, profiles)) != before


def git(*args, cwd):
    subprocess.run(
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
        cwd=cwd, check=True, capture_output=True,
    )


def test_profiles_fetch_is_sparse_and_idempotent(runner, tmp_path, monkeypatch):
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
    monkeypatch.chdir(parent)
    remote = f"file://{upstream}"

    result = runner.invoke(cli, ["profiles", "fetch", "--remote", remote])
    assert result.exit_code == 0, result.output
    assert (parent / ".orca-slicer/resources/profiles/BBL/x.json").is_file()
    assert not (parent / ".orca-slicer/src").exists()

    result = runner.invoke(cli, ["profiles", "fetch", "--remote", remote])
    assert result.exit_code == 0, result.output
    assert "already at" in result.output
