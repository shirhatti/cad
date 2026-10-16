"""
OrcaSlicer printer profiles: fetch, flatten, lint, and verify.

OrcaSlicer's CLI loads each profile file as-is: it does NOT resolve the
`inherits` chain the way the GUI does. A leaf profile like
"Generic PLA @BBL A1.json" holds only a handful of keys, so passing it
directly silently slices with built-in defaults for everything else (a
200x200 bed, 200C nozzle, 0 g/cm3 filament density, ...). So scad-tools
flattens each profile into a complete config before slicing, and checks
afterwards that the slicer actually applied it (`verify_effective_settings`).

Local overrides in .orca-profiles-local/ are layered on top of the upstream
profile with the same `type` and `name`. A local file with an explicit
`inherits` instead defines a new profile built on that upstream parent.
"""

import functools
import json
import re
import subprocess
from pathlib import Path

import click

# Upstream profiles come from this submodule, pinned to the OrcaSlicer release
# in toolchain.toml. Slicing only needs its resources/profiles subtree.
ORCA_SUBMODULE = Path(".orca-slicer")
ORCA_UPSTREAM_URL = "https://github.com/OrcaSlicer/OrcaSlicer.git"
ORCA_PROFILES_SUBTREE = "resources/profiles"
ORCA_PROFILES_ROOT = ORCA_SUBMODULE / ORCA_PROFILES_SUBTREE

# Default profile paths (relative to repo root)
ORCA_VENDOR = "BBL"
ORCA_PROFILES_UPSTREAM = ORCA_PROFILES_ROOT / ORCA_VENDOR
ORCA_PROFILES_LOCAL = Path(".orca-profiles-local") / ORCA_VENDOR
ORCA_MACHINE_PROFILE = ORCA_PROFILES_LOCAL / "machine/Bambu Lab A1 0.4 nozzle.json"
ORCA_PROCESS_PROFILE = ORCA_PROFILES_LOCAL / "process/0.20mm Standard @BBL A1.json"
ORCA_FILAMENT_PROFILE = ORCA_PROFILES_UPSTREAM / "filament/Generic PLA @BBL A1.json"
ORCA_PROFILES = {
    "machine": ORCA_MACHINE_PROFILE,
    "process": ORCA_PROCESS_PROFILE,
    "filament": ORCA_FILAMENT_PROFILE,
}

# Profile bookkeeping, not slicer settings: dropped from flattened profiles'
# comparisons since the slicer rewrites or discards them.
META_KEYS = {
    "type", "name", "inherits", "from", "setting_id", "instantiation",
    "description", "compatible_printers", "compatible_printers_condition",
    "compatible_prints", "compatible_prints_condition", "filament_id",
    "print_settings_id", "printer_settings_id", "filament_settings_id",
    "version", "is_custom_defined",
}

# Settings OrcaSlicer 2.3.1's CLI is observed to rewrite after loading a
# complete profile. Each maps to why, so a new mismatch fails loudly instead.
SLICER_ADJUSTED = {
    "machine_max_acceleration_x": "CLI caps machine limits at 6000 for Bambu printers",
    "machine_max_acceleration_y": "CLI caps machine limits at 6000 for Bambu printers",
    "machine_max_acceleration_travel": "CLI caps machine limits at 6000 for Bambu printers",
}


# =============================================================================
# Resolution
# =============================================================================


@functools.cache
def upstream_index(vendor_dir: Path = ORCA_PROFILES_UPSTREAM) -> dict[tuple[str, str], Path]:
    """Map (type, name) -> file for every upstream profile of one vendor."""
    index = {}
    for kind in ("machine", "process", "filament"):
        for path in sorted((vendor_dir / kind).glob("*.json")):
            try:
                data = json.loads(path.read_text())
            except (OSError, json.JSONDecodeError):
                continue
            if "name" in data:
                index[(data.get("type", kind), data["name"])] = path
    return index


@functools.cache
def known_keys(kind: str, profiles_root: Path = ORCA_PROFILES_ROOT) -> frozenset[str]:
    """Every key any upstream vendor uses for this profile type."""
    keys: set[str] = set()
    for path in profiles_root.glob(f"*/{kind}/*.json"):
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError, UnicodeDecodeError):
            continue
        if isinstance(data, dict):
            keys.update(data)
    return frozenset(keys)


def _load(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as e:
        raise click.ClickException(f"Can't read profile {path}: {e}")


def resolve_upstream(kind: str, name: str, vendor_dir: Path = ORCA_PROFILES_UPSTREAM, _seen=()) -> dict:
    """Flatten an upstream profile by name, applying its inherits chain."""
    if name in _seen:
        raise click.ClickException(f"Profile inheritance cycle: {' -> '.join((*_seen, name))}")
    path = upstream_index(vendor_dir).get((kind, name))
    if path is None:
        raise click.ClickException(f"No upstream {kind} profile named {name!r} in {vendor_dir}")
    data = _load(path)
    parent = data.get("inherits")
    base = resolve_upstream(kind, parent, vendor_dir, (*_seen, name)) if parent else {}
    return {**base, **data}


def base_profile(kind: str, data: dict, vendor_dir: Path = ORCA_PROFILES_UPSTREAM) -> dict:
    """
    The flattened profile a file builds on: its explicit `inherits` parent, or
    else (for a local override) the upstream profile it shares a name with.
    """
    if data.get("inherits"):
        return resolve_upstream(kind, data["inherits"], vendor_dir)
    if (kind, data.get("name")) in upstream_index(vendor_dir):
        return resolve_upstream(kind, data["name"], vendor_dir)
    return {}


def flatten_profile(kind: str, path: Path, vendor_dir: Path = ORCA_PROFILES_UPSTREAM) -> dict:
    """A complete, inherits-free profile the CLI can load on its own."""
    data = _load(path)
    if data.get("type", kind) != kind:
        raise click.ClickException(f"{path} is a {data.get('type')!r} profile, expected {kind!r}")
    flat = {**base_profile(kind, data, vendor_dir), **data}
    flat.pop("inherits", None)
    return flat


def write_flat_profiles(dest: Path, profiles: dict[str, Path] = ORCA_PROFILES) -> dict[str, Path]:
    """Flatten each profile into dest/<kind>.json; returns kind -> path."""
    dest.mkdir(parents=True, exist_ok=True)
    out = {}
    for kind, path in profiles.items():
        out[kind] = dest / f"{kind}.json"
        out[kind].write_text(json.dumps(flatten_profile(kind, path), indent=4, sort_keys=True) + "\n")
    return out


# =============================================================================
# Verification
# =============================================================================

_NUM_RE = re.compile(r"^-?\d+(\.\d+)?$")


def _normalize(value) -> list[str]:
    """Compare config values the way OrcaSlicer serializes them."""
    items = value if isinstance(value, list) else [value]
    out = []
    for item in items:
        s = str(item)
        if _NUM_RE.match(s):
            s = repr(float(s))
        # Points: "0.5x0.5" in profiles, "0.5,0.5" in project_settings
        out.append(s.replace("x", ",") if re.fullmatch(r"[\d.,x-]+", s) else s)
    return out


def verify_effective_settings(
    flat: dict[str, dict], effective: dict, local_keys: dict[str, set[str]] | None = None
) -> tuple[list[str], list[str]]:
    """
    Compare flattened profiles with the settings the slicer reports it used
    (Metadata/project_settings.config). Returns (errors, warnings):

    - a value that differs is an error (unless listed in SLICER_ADJUSTED),
      since it means the slice doesn't match the profile;
    - a key the slicer dropped is an error for a local override (the override
      does nothing) and a warning for upstream keys (upstream profiles carry
      keys newer or older than the pinned slicer).
    """
    errors, warnings = [], []
    local_keys = local_keys or {}
    for kind, profile in flat.items():
        for key, value in sorted(profile.items()):
            if key in META_KEYS:
                continue
            if key not in effective:
                msg = f"{kind}.{key} is not a setting this slicer knows; ignored"
                (errors if key in local_keys.get(kind, ()) else warnings).append(msg)
            elif _normalize(value) != _normalize(effective[key]) and key not in SLICER_ADJUSTED:
                errors.append(f"{kind}.{key}: profile has {value!r}, slicer used {effective[key]!r}")
    return errors, warnings


def lint_profiles(profiles: dict[str, Path] = ORCA_PROFILES) -> tuple[list[str], list[str]]:
    """
    Static checks on the profiles (no slicer needed). Returns (errors, warnings).

    - errors: unreadable files, broken inheritance, and keys no upstream profile
      of that type uses anywhere (almost certainly a typo).
    - warnings: local override keys whose value equals what they'd inherit
      anyway (dead config, and a trap when upstream later changes).
    """
    errors, warnings = [], []
    for kind, path in profiles.items():
        try:
            data = _load(path)
            base = base_profile(kind, data)
        except click.ClickException as e:
            errors.append(e.message)
            continue
        if not path.is_relative_to(ORCA_PROFILES_LOCAL):
            continue
        known = known_keys(kind)
        for key, value in data.items():
            if key in META_KEYS:
                continue
            if known and key not in known:
                errors.append(f"{path}: unknown {kind} key {key!r} (typo?)")
            elif key in base and _normalize(base[key]) == _normalize(value):
                warnings.append(f"{path}: {key} = {value!r} is already the inherited value")
    return errors, warnings


def local_override_keys(profiles: dict[str, Path] = ORCA_PROFILES) -> dict[str, set[str]]:
    """The non-meta keys each local override sets, by profile type."""
    return {
        kind: set(_load(path)) - META_KEYS
        for kind, path in profiles.items()
        if path.is_relative_to(ORCA_PROFILES_LOCAL)
    }


# =============================================================================
# Fetching the pinned upstream profiles
# =============================================================================


@functools.cache
def orca_profiles_commit() -> str | None:
    """
    The commit the .orca-slicer submodule is pinned to at HEAD (its gitlink),
    readable without the submodule being checked out. None outside a git
    checkout or if the submodule isn't recorded.
    """
    result = subprocess.run(
        ["git", "rev-parse", f"HEAD:{ORCA_SUBMODULE}"], capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else None


def missing_orca_profiles(profiles: dict[str, Path] = ORCA_PROFILES) -> list[Path]:
    """Slicer profiles that aren't on disk (e.g. the submodule isn't fetched)."""
    return [p for p in profiles.values() if not p.is_file()]


def _git(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)


def require_profiles() -> None:
    """Fail once up front, with a fix, when the slicer profiles are missing."""
    missing = missing_orca_profiles()
    if missing:
        listing = "\n".join(f"  {p}" for p in missing)
        raise click.ClickException(
            f"Slicer profile(s) not found:\n{listing}\n"
            "Fetch the pinned OrcaSlicer profiles with `uv run scad-tools profiles fetch` "
            "(or `git submodule update --init --depth 1`)."
        )


# =============================================================================
# CLI
# =============================================================================


@click.group()
def profiles() -> None:
    """Manage the OrcaSlicer printer profiles."""


@profiles.command()
@click.option("--remote", default=ORCA_UPSTREAM_URL, show_default=True, help="Repository to fetch from")
def fetch(remote: str) -> None:
    """Fetch the pinned OrcaSlicer profiles into .orca-slicer.

    Reads the commit from the .orca-slicer submodule gitlink and does a
    blobless, depth-1, sparse fetch of only resources/profiles at that commit,
    instead of cloning the whole OrcaSlicer source tree. Idempotent; an
    existing submodule checkout is moved to the pinned commit but keeps its
    own sparse-checkout settings.
    """
    sha = orca_profiles_commit()
    if not sha:
        raise click.ClickException(f"No {ORCA_SUBMODULE} submodule pinned at HEAD (not in the repo root?)")

    dest = ORCA_SUBMODULE
    dest.mkdir(exist_ok=True)
    # An uninitialized submodule is an empty dir, where git commands resolve
    # to the parent repo; only treat dest as a checkout if it is its own root.
    toplevel = _git("rev-parse", "--show-toplevel", cwd=dest).stdout.strip()
    is_checkout = bool(toplevel) and Path(toplevel).resolve() == dest.resolve()

    if is_checkout and _git("rev-parse", "HEAD", cwd=dest).stdout.strip() == sha:
        click.echo(f"✓ {dest} already at {sha[:12]}")
        return
    if not is_checkout:
        for args in (("init", "-q"), ("sparse-checkout", "set", ORCA_PROFILES_SUBTREE)):
            result = _git(*args, cwd=dest)
            if result.returncode != 0:
                raise click.ClickException(f"git {' '.join(args)} failed: {result.stderr.strip()}")

    if _git("cat-file", "-e", f"{sha}^{{commit}}", cwd=dest).returncode != 0:
        click.echo(f"Fetching {ORCA_PROFILES_SUBTREE} at {sha[:12]} from {remote}...")
        result = _git("fetch", "-q", "--depth", "1", "--filter=blob:none", remote, sha, cwd=dest)
        if result.returncode != 0:
            raise click.ClickException(f"git fetch failed: {result.stderr.strip()}")
    result = _git("checkout", "-q", sha, cwd=dest)
    if result.returncode != 0:
        raise click.ClickException(f"git checkout failed: {result.stderr.strip()}")
    click.secho(f"✓ {dest} at {sha[:12]}", fg="green")


@profiles.command()
@click.argument("kind", type=click.Choice(sorted(ORCA_PROFILES)))
def show(kind: str) -> None:
    """Print the fully resolved (flattened) profile the slicer is given."""
    require_profiles()
    click.echo(json.dumps(flatten_profile(kind, ORCA_PROFILES[kind]), indent=4, sort_keys=True))


@profiles.command()
@click.option("--strict", is_flag=True, help="Treat warnings as errors")
def lint(strict: bool) -> None:
    """Check the profiles resolve and the local overrides are live and spelled right."""
    require_profiles()
    errors, warnings = lint_profiles()
    for msg in errors:
        click.secho(f"  ✗ {msg}", fg="red", err=True)
    for msg in warnings:
        click.secho(f"  ⚠ {msg}", fg="yellow", err=True)
    if errors or (strict and warnings):
        raise click.ClickException(f"{len(errors)} error(s), {len(warnings)} warning(s) in slicer profiles")
    click.secho(f"✓ Profiles OK ({len(warnings)} warning(s))", fg="green")
