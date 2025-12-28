#!/usr/bin/env python3
"""
Unified OpenSCAD tooling CLI.

Single source of truth for file discovery, rendering, linting, and other operations.
Replaces scattered find commands in justfile and CI with consistent exclusion logic.

Usage:
    uv run scad-tools list            # List renderable models
    uv run scad-tools list --tests    # List test files
    uv run scad-tools lint            # Lint all models
    uv run scad-tools render          # Render all models to STL + PNG
    uv run scad-tools render-file F   # Render single file
    uv run scad-tools slice           # Slice all STL to 3MF
    uv run scad-tools check           # Validate models render
    uv run scad-tools test            # Run unit tests
    uv run scad-tools gui FILE        # Open in OpenSCAD GUI

Environment variables for GHCR caching (auto-enabled in CI):
    GITHUB_REPOSITORY    - Owner/repo for cache (e.g., "owner/repo")
    GITHUB_TOKEN         - Token for GHCR authentication
    GITHUB_REF_NAME      - Branch name (updates 'latest' tag on main)
    SKIP_CACHE=1         - Disable caching
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

import click
import oras.client

# Central exclusion patterns - the single source of truth
EXCLUDE_SUFFIXES = {
    "test": "_test.scad",       # Unit test files
    "constants": "_constants.scad",  # Shared constants
    "reference": "_reference.scad",  # Visualization-only models
    "lib": "_lib.scad",         # Shared library modules
}


def find_openscad() -> str:
    """
    Find OpenSCAD binary, checking platform-specific locations.

    Search order:
    1. macOS: Homebrew cask install location
    2. PATH: 'openscad' command
    """
    # macOS: Check Homebrew cask location
    if sys.platform == "darwin":
        try:
            result = subprocess.run(
                ["brew", "info", "--cask", "openscad", "--json=v2"],
                capture_output=True,
                text=True,
                check=True,
            )
            info = json.loads(result.stdout)
            app_name = None
            for artifact in info["casks"][0].get("artifacts", []):
                if isinstance(artifact, dict) and "app" in artifact:
                    app_name = artifact["app"][0]
                    break
            if app_name:
                openscad_bin = Path("/Applications") / app_name / "Contents/MacOS/OpenSCAD"
                if openscad_bin.exists():
                    return str(openscad_bin)
        except (subprocess.CalledProcessError, json.JSONDecodeError, KeyError, IndexError):
            pass

    # Fall back to PATH
    openscad = shutil.which("openscad")
    if openscad:
        return openscad

    raise click.ClickException(
        "OpenSCAD not found. Install from https://openscad.org/downloads.html"
    )


def needs_xvfb() -> bool:
    """Check if we need xvfb-run for headless operation."""
    # macOS and Windows don't need xvfb
    if sys.platform != "linux":
        return False

    # If DISPLAY is set, we have a display
    if os.environ.get("DISPLAY"):
        return False

    # Check if xvfb-run is available
    return shutil.which("xvfb-run") is not None


def run_openscad(openscad: str, args: list[str]) -> subprocess.CompletedProcess:
    """Run OpenSCAD, using xvfb-run if needed for headless operation."""
    cmd = [openscad] + args
    if needs_xvfb():
        cmd = ["xvfb-run", "--auto-servernum"] + cmd
    return subprocess.run(cmd, capture_output=True, text=True)


# =============================================================================
# ORAS Caching
# =============================================================================


def get_cache_config() -> dict | None:
    """
    Get ORAS cache configuration from environment.

    Returns None if caching is disabled or not configured.
    Caching is enabled when GITHUB_REPOSITORY is set.
    """
    repo = os.environ.get("GITHUB_REPOSITORY")
    if not repo or os.environ.get("SKIP_CACHE") == "1":
        return None

    registry = os.environ.get("REGISTRY", "ghcr.io")
    repo_owner, repo_name = repo.split("/", 1)

    return {
        "registry": registry,
        "repo_owner": repo_owner,
        "repo_name": repo_name,
        "is_main_branch": os.environ.get("GITHUB_REF_NAME") == "main",
    }


def compute_file_hash(file_path: Path) -> str:
    """Compute SHA256 hash of a file."""
    sha256 = hashlib.sha256()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha256.update(chunk)
    return sha256.hexdigest()


def find_scad_dependencies(scad_file: Path) -> list[Path]:
    """
    Find all files included/used by a .scad file.

    Parses include <...> and use <...> statements and resolves paths
    relative to the scad file's directory.
    """
    import re

    deps = []
    base_dir = scad_file.parent

    try:
        content = scad_file.read_text()
        # Match include <file.scad> and use <file.scad>
        pattern = r'(?:include|use)\s*<([^>]+)>'
        for match in re.finditer(pattern, content):
            dep_path = base_dir / match.group(1)
            if dep_path.exists():
                deps.append(dep_path)
                # Recursively find dependencies of dependencies
                deps.extend(find_scad_dependencies(dep_path))
    except Exception:
        pass

    return deps


def compute_model_hash(scad_file: Path) -> str:
    """
    Compute hash of a .scad file and all its dependencies.

    This ensures cache invalidation when any included file changes.
    """
    sha256 = hashlib.sha256()

    # Hash the main file
    sha256.update(scad_file.read_bytes())

    # Hash all dependencies (sorted for determinism)
    deps = find_scad_dependencies(scad_file)
    for dep in sorted(set(deps)):
        sha256.update(dep.read_bytes())

    return sha256.hexdigest()


def compute_string_hash(s: str) -> str:
    """Compute SHA256 hash of a string."""
    return hashlib.sha256(s.encode()).hexdigest()


def get_openscad_version(openscad: str) -> str:
    """Get OpenSCAD version string."""
    try:
        result = subprocess.run(
            [openscad, "--version"], capture_output=True, text=True
        )
        return result.stderr.strip() or result.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def get_oras_client(registry: str) -> oras.client.OrasClient:
    """
    Get an ORAS client configured for the given registry.

    Authentication is handled via environment (GITHUB_TOKEN for GHCR).
    """
    client = oras.client.OrasClient()

    # Authenticate with GHCR using GITHUB_TOKEN if available
    token = os.environ.get("GITHUB_TOKEN")
    if token and "ghcr.io" in registry:
        client.login(
            hostname="ghcr.io",
            username="token",
            password=token,
        )

    return client


def oras_pull(oci_ref: str, output_dir: Path, registry: str = "ghcr.io") -> bool:
    """
    Pull artifacts from OCI registry using ORAS.

    Returns True if successful, False otherwise.
    """
    try:
        client = get_oras_client(registry)
        client.pull(target=oci_ref, outdir=str(output_dir))
        return True
    except Exception as e:
        # Log the actual error for debugging
        if os.environ.get("DEBUG"):
            click.echo(f"ORAS pull failed: {e}", err=True)
        return False


def oras_push(
    oci_ref: str,
    files: list[str],
    registry: str = "ghcr.io",
) -> bool:
    """
    Push artifacts to OCI registry using ORAS.

    Args:
        oci_ref: OCI reference (registry/repo:tag)
        files: List of file paths to push
        registry: Registry hostname for authentication

    Returns True if successful, False otherwise.
    """
    try:
        client = get_oras_client(registry)
        # oras-py needs to run from the directory containing the files
        # and files should be relative paths
        if files:
            work_dir = Path(files[0]).parent
            rel_files = [Path(f).name for f in files]
            original_dir = os.getcwd()
            try:
                os.chdir(work_dir)
                client.push(files=rel_files, target=oci_ref)
            finally:
                os.chdir(original_dir)
        return True
    except Exception as e:
        # Log the actual error for debugging
        click.echo(f"ORAS push failed: {e}", err=True)
        return False


def find_scad_files(
    base_path: Path,
    include_tests: bool = False,
    include_libs: bool = False,
    include_constants: bool = False,
    include_reference: bool = False,
    only_tests: bool = False,
) -> list[Path]:
    """
    Find OpenSCAD files with consistent exclusion logic.

    By default, returns only renderable model files (excludes tests, libs, constants, reference).
    Use flags to include specific categories or only_tests to get test files.
    """
    all_files = sorted(base_path.rglob("*.scad"))

    if only_tests:
        return [f for f in all_files if f.name.endswith(EXCLUDE_SUFFIXES["test"])]

    result = []
    for f in all_files:
        # Check each exclusion category
        if f.name.endswith(EXCLUDE_SUFFIXES["test"]) and not include_tests:
            continue
        if f.name.endswith(EXCLUDE_SUFFIXES["lib"]) and not include_libs:
            continue
        if f.name.endswith(EXCLUDE_SUFFIXES["constants"]) and not include_constants:
            continue
        if f.name.endswith(EXCLUDE_SUFFIXES["reference"]) and not include_reference:
            continue
        result.append(f)

    return result


def get_output_name(scad_file: Path, base_path: Path) -> str:
    """Generate output name: project__basename format."""
    rel_path = scad_file.relative_to(base_path)
    project_name = str(rel_path.parent)
    basename = scad_file.stem
    return f"{project_name}__{basename}"


@click.group()
@click.option(
    "--base-path",
    type=click.Path(exists=True, path_type=Path),
    default=Path("projects"),
    help="Base path to search for .scad files",
)
@click.pass_context
def cli(ctx: click.Context, base_path: Path) -> None:
    """Unified OpenSCAD tooling CLI."""
    ctx.ensure_object(dict)
    ctx.obj["base_path"] = base_path


@cli.command(name="list")
@click.option("--tests", is_flag=True, help="List only test files")
@click.option("--libs", is_flag=True, help="Include library files")
@click.option("--all", "include_all", is_flag=True, help="Include all file types")
@click.option("--output-names", is_flag=True, help="Show output names instead of paths")
@click.option("--null", "-0", is_flag=True, help="Null-separated output (for xargs -0)")
@click.pass_context
def list_files(
    ctx: click.Context,
    tests: bool,
    libs: bool,
    include_all: bool,
    output_names: bool,
    null: bool,
) -> None:
    """List OpenSCAD files matching criteria."""
    base_path = ctx.obj["base_path"]

    files = find_scad_files(
        base_path,
        include_tests=include_all,
        include_libs=libs or include_all,
        include_constants=include_all,
        include_reference=include_all,
        only_tests=tests,
    )

    separator = "\0" if null else "\n"
    for f in files:
        if output_names:
            click.echo(get_output_name(f, base_path), nl=not null)
        else:
            click.echo(str(f), nl=not null)
        if null:
            sys.stdout.write("\0")


@cli.command()
@click.option("--strict", is_flag=True, help="Treat warnings as errors")
@click.option("--quiet", is_flag=True, help="Only show errors")
@click.pass_context
def lint(ctx: click.Context, strict: bool, quiet: bool) -> None:
    """Lint OpenSCAD files for Customizer compliance."""
    # Import here to avoid circular dependency
    from scripts.customizer_lint import lint_file

    base_path = ctx.obj["base_path"]
    files = find_scad_files(base_path)

    total_errors = 0
    total_warnings = 0
    failed = 0

    for f in files:
        result = lint_file(f)

        for error in result.errors:
            click.secho(str(error), fg="red")
            total_errors += 1

        if not quiet:
            for warning in result.warnings:
                click.secho(str(warning), fg="yellow")
                total_warnings += 1

        if not result.passed or (strict and result.warnings):
            failed += 1

    # Summary
    click.echo()
    passed = len(files) - failed
    if failed == 0:
        click.secho(f"All {len(files)} file(s) passed Customizer linting", fg="green")
    else:
        click.secho(f"{failed} file(s) failed, {passed} passed", fg="red")
        click.echo(f"  {total_errors} error(s), {total_warnings} warning(s)")

    if strict:
        sys.exit(1 if (total_errors + total_warnings) > 0 else 0)
    sys.exit(1 if total_errors > 0 else 0)


def render_single_model(
    scad_file: Path,
    base_path: Path,
    output_dir: Path,
    openscad: str,
    cache_config: dict | None,
) -> bool:
    """
    Render a single model to STL and PNG, with optional caching.

    Returns True on success, False on failure.
    """
    out_name = get_output_name(scad_file, base_path)
    rel_path = scad_file.relative_to(base_path)
    project_name = str(rel_path.parent)
    basename = scad_file.stem

    stl_dir = output_dir / "stl"
    preview_dir = output_dir / "preview"
    stl_dir.mkdir(parents=True, exist_ok=True)
    preview_dir.mkdir(parents=True, exist_ok=True)

    stl_file = stl_dir / f"{out_name}.stl"
    png_file = preview_dir / f"{out_name}.png"

    # Check cache if enabled
    if cache_config:
        file_hash = compute_model_hash(scad_file)  # includes dependencies
        version_hash = compute_string_hash(get_openscad_version(openscad))[:8]
        cache_tag = f"{version_hash}-{file_hash[:12]}"

        registry = cache_config["registry"]
        oci_base = (
            f"{registry}/{cache_config['repo_owner']}/"
            f"{cache_config['repo_name']}/renders/{project_name}/{basename}"
        )
        oci_ref = f"{oci_base}:{cache_tag}"

        click.echo(f"Checking cache for {out_name}...")

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            if oras_pull(oci_ref, temp_path, registry):
                # Cache hit - copy files to output
                cached_stl = temp_path / f"{out_name}.stl"
                cached_png = temp_path / f"{out_name}.png"
                if cached_stl.exists():
                    shutil.copy(cached_stl, stl_file)
                if cached_png.exists():
                    shutil.copy(cached_png, png_file)
                click.secho(f"  ✓ Cache hit", fg="green")
                return True

        click.echo(f"  ✗ Cache miss, rendering...")

    # Render STL
    click.echo(f"Rendering {scad_file} -> {stl_file}")
    result = run_openscad(openscad, ["-o", str(stl_file), str(scad_file)])
    if result.returncode != 0:
        click.secho(f"  ✗ STL render failed: {result.stderr}", fg="red", err=True)
        return False

    # Render PNG preview
    click.echo(f"Rendering preview -> {png_file}")
    result = run_openscad(
        openscad,
        [
            "-o", str(png_file),
            "--autocenter", "--viewall",
            "--camera=0,0,0,55,0,25,500",
            str(scad_file),
        ],
    )
    if result.returncode != 0:
        click.secho(f"  ⚠ Preview render failed (continuing): {result.stderr}", fg="yellow")

    click.secho(f"  ✓ OK", fg="green")

    # Push to cache if enabled
    if cache_config and stl_file.exists():
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            # Copy files to temp dir for push
            shutil.copy(stl_file, temp_path / f"{out_name}.stl")
            if png_file.exists():
                shutil.copy(png_file, temp_path / f"{out_name}.png")

            push_files = [str(temp_path / f"{out_name}.stl")]
            if png_file.exists():
                push_files.append(str(temp_path / f"{out_name}.png"))

            # Push to content-addressed tag
            if oras_push(oci_ref, push_files, registry):
                click.echo(f"  ✓ Cached {out_name}")
            else:
                click.echo(f"  ⚠ Failed to cache (continuing)")

            # Update latest tag on main branch
            if cache_config["is_main_branch"]:
                oci_latest = f"{oci_base}:latest"
                oras_push(oci_latest, push_files, registry)

    return True


@cli.command()
@click.option("--output-dir", type=click.Path(path_type=Path), default=Path("artifacts"))
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@click.pass_context
def render(ctx: click.Context, output_dir: Path, openscad: str | None) -> None:
    """Render all models to STL and PNG preview.

    Automatically uses GHCR caching when GITHUB_REPOSITORY is set.
    """
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path)
    cache_config = get_cache_config()

    if cache_config:
        click.echo(f"ORAS caching enabled: {cache_config['registry']}")

    failed = []
    for f in files:
        if not render_single_model(f, base_path, output_dir, openscad, cache_config):
            failed.append(f)

    if failed:
        click.echo(f"\n{len(failed)} file(s) failed to render", err=True)
        sys.exit(1)

    click.echo(f"\n✓ Rendered {len(files)} model(s) to {output_dir}")


@cli.command(name="render-file")
@click.argument("file", type=click.Path(exists=True, path_type=Path))
@click.option("--output-dir", type=click.Path(path_type=Path), default=Path("artifacts"))
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@click.pass_context
def render_file(ctx: click.Context, file: Path, output_dir: Path, openscad: str | None) -> None:
    """Render a single file to STL and PNG preview."""
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()

    # Resolve file path relative to base_path if needed
    if not str(file).startswith(str(base_path)):
        # Try to find it under base_path
        potential = base_path / file
        if potential.exists():
            file = potential

    if not render_single_model(file, base_path, output_dir, openscad, cache_config=None):
        sys.exit(1)


@cli.command()
@click.argument("file", type=click.Path(exists=True, path_type=Path))
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
def gui(file: Path, openscad: str | None) -> None:
    """Open a file in OpenSCAD GUI."""
    openscad = openscad or find_openscad()
    subprocess.Popen([openscad, str(file)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    click.echo(f"Opened {file} in OpenSCAD")


@cli.command()
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@click.pass_context
def check(ctx: click.Context, openscad: str | None) -> None:
    """Validate all models render without errors."""
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path)

    failed = []
    for f in files:
        click.echo(f"Checking {f}...")

        result = run_openscad(openscad, ["--export-format", "csg", "-o", "/dev/null", str(f)])
        if result.returncode != 0:
            click.echo(f"  ✗ FAILED")
            failed.append(f)
        else:
            click.echo(f"  ✓ OK")

    if failed:
        click.echo(f"\n{len(failed)} file(s) failed validation", err=True)
        sys.exit(1)

    click.echo(f"\n✓ All {len(files)} model(s) validated successfully")


@cli.command()
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@click.pass_context
def test(ctx: click.Context, openscad: str | None) -> None:
    """Run OpenSCAD unit tests."""
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path, only_tests=True)

    if not files:
        click.echo(f"No test files found in {base_path}")
        sys.exit(0)

    failed = []
    for f in files:
        click.echo(f"Running {f}...")

        result = run_openscad(
            openscad, ["--hardwarnings", "-o", "/dev/null", "--export-format", "csg", str(f)]
        )

        # Print ECHO output for visibility
        for line in result.stderr.splitlines():
            if line.startswith("ECHO:"):
                click.echo(f"  {line}")

        # Check for assertion failures
        if "Assertion" in result.stderr and "failed" in result.stderr:
            click.echo(f"  ✗ FAILED")
            failed.append(f)
        elif result.returncode != 0:
            click.echo(f"  ✗ FAILED (exit code {result.returncode})")
            failed.append(f)
        else:
            click.echo(f"  ✓ PASSED")

    click.echo()
    if failed:
        click.echo(f"✗ {len(failed)}/{len(files)} test(s) failed", err=True)
        sys.exit(1)

    click.echo(f"✓ All {len(files)} test(s) passed")


# =============================================================================
# Configuration
# =============================================================================


def get_slice_exclusions() -> dict[str, str]:
    """
    Get slice exclusions from pyproject.toml.

    Config uses real paths (e.g., "rack/wiim_amp_retention_bracket.scad").
    Returns dict mapping output names (e.g., "rack__wiim_amp_retention_bracket") to exclusion reasons.
    """
    pyproject = Path("pyproject.toml")
    if not pyproject.exists():
        return {}

    try:
        with open(pyproject, "rb") as f:
            config = tomllib.load(f)
        raw_exclusions = config.get("tool", {}).get("scad-tools", {}).get("slice", {}).get("exclude", {})

        # Convert paths to output names: "rack/model.scad" -> "rack__model"
        exclusions = {}
        for path, reason in raw_exclusions.items():
            # Remove .scad extension and replace / with __
            output_name = path.removesuffix(".scad").replace("/", "__")
            exclusions[output_name] = reason
        return exclusions
    except Exception:
        return {}


# =============================================================================
# OrcaSlicer Support
# =============================================================================

# Default profile paths (relative to repo root)
ORCA_PROFILES_UPSTREAM = Path(".orca-slicer/resources/profiles/BBL")
ORCA_PROFILES_LOCAL = Path(".orca-profiles-local/BBL")
ORCA_MACHINE_PROFILE = ORCA_PROFILES_LOCAL / "machine/Bambu Lab A1 0.4 nozzle.json"
ORCA_PROCESS_PROFILE = ORCA_PROFILES_LOCAL / "process/0.20mm Standard @BBL A1.json"
ORCA_FILAMENT_PROFILE = ORCA_PROFILES_UPSTREAM / "filament/Generic PLA @BBL A1.json"


def find_orca_slicer() -> str:
    """
    Find OrcaSlicer binary, checking platform-specific locations.
    """
    # macOS: Check standard app location
    if sys.platform == "darwin":
        macos_path = Path("/Applications/OrcaSlicer.app/Contents/MacOS/OrcaSlicer")
        if macos_path.exists():
            return str(macos_path)

    # Linux/PATH fallback
    orca = shutil.which("orca-slicer")
    if orca:
        return orca

    raise click.ClickException(
        "OrcaSlicer not found. Install from https://github.com/OrcaSlicer/OrcaSlicer/releases"
    )


def get_orca_version(orca_bin: str) -> str:
    """Get OrcaSlicer version string."""
    try:
        result = subprocess.run([orca_bin, "--help"], capture_output=True, text=True)
        # Extract version from help output (e.g., "OrcaSlicer v2.3.1")
        for line in result.stdout.splitlines() + result.stderr.splitlines():
            if "v" in line.lower() and "." in line:
                return line.strip()
        return "unknown"
    except Exception:
        return "unknown"


def run_orca_slicer(orca_bin: str, args: list[str]) -> subprocess.CompletedProcess:
    """Run OrcaSlicer, using xvfb-run if needed for headless operation."""
    cmd = [orca_bin] + args
    if needs_xvfb():
        cmd = ["xvfb-run", "--auto-servernum"] + cmd
    return subprocess.run(cmd, capture_output=True, text=True)


def compute_profiles_hash() -> str:
    """Compute hash of local slicer profile overrides."""
    local_profiles = Path(".orca-profiles-local")
    if not local_profiles.exists():
        return "no-local-profiles"

    hasher = hashlib.sha256()
    for profile_file in sorted(local_profiles.rglob("*")):
        if profile_file.is_file():
            hasher.update(profile_file.read_bytes())
    return hasher.hexdigest()[:16]


def slice_single_model(
    model_name: str,
    artifacts_dir: Path,
    orca_bin: str,
    cache_config: dict | None,
) -> bool:
    """
    Slice a single STL model to 3MF, with optional caching.

    Args:
        model_name: Output name (e.g., "rack__retention_bracket")
        artifacts_dir: Directory containing stl/ and for gcode/ output
        orca_bin: Path to OrcaSlicer binary
        cache_config: ORAS cache configuration or None

    Returns True on success, False on failure.
    """
    stl_file = artifacts_dir / "stl" / f"{model_name}.stl"
    gcode_dir = artifacts_dir / "gcode"
    logs_dir = artifacts_dir / "logs"
    gcode_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    output_file = gcode_dir / f"{model_name}.3mf"
    log_file = logs_dir / f"{model_name}.log"

    if not stl_file.exists():
        click.secho(f"  ✗ STL not found: {stl_file}", fg="red", err=True)
        return False

    # Extract project/model from name (e.g., "rack__model" -> "rack/model")
    model_path = model_name.replace("__", "/")

    # Check cache if enabled
    if cache_config:
        stl_hash = compute_file_hash(stl_file)
        profiles_hash = compute_profiles_hash()[:8]
        slicer_hash = compute_string_hash(get_orca_version(orca_bin))[:8]
        cache_tag = f"{slicer_hash}-{profiles_hash}-{stl_hash[:12]}"

        registry = cache_config["registry"]
        oci_base = (
            f"{registry}/{cache_config['repo_owner']}/"
            f"{cache_config['repo_name']}/slices/{model_path}"
        )
        oci_ref = f"{oci_base}:{cache_tag}"

        click.echo(f"Checking slice cache for {model_name}...")

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            if oras_pull(oci_ref, temp_path, registry):
                # Cache hit - copy files to output
                cached_3mf = temp_path / f"{model_name}.3mf"
                cached_log = temp_path / f"{model_name}.log"
                if cached_3mf.exists():
                    shutil.copy(cached_3mf, output_file)
                if cached_log.exists():
                    shutil.copy(cached_log, log_file)
                click.secho(f"  ✓ Cache hit", fg="green")
                return True

        click.echo(f"  ✗ Cache miss, slicing...")

    # Build settings argument: machine;process;filament
    settings = f"{ORCA_MACHINE_PROFILE};{ORCA_PROCESS_PROFILE};{ORCA_FILAMENT_PROFILE}"

    # Make paths absolute for OrcaSlicer
    abs_input = stl_file.resolve()
    abs_output = output_file.resolve()

    click.echo(f"Slicing {model_name}...")
    result = run_orca_slicer(
        orca_bin,
        [
            "--load-settings", settings,
            "--slice", "0",
            "--export-3mf", str(abs_output),
            str(abs_input),
        ],
    )

    # Write log
    log_content = result.stdout + result.stderr
    log_file.write_text(log_content)

    if not output_file.exists():
        click.secho(f"  ✗ Slicing failed", fg="red", err=True)
        if log_content:
            for line in log_content.splitlines()[-5:]:
                click.echo(f"    {line}")
        return False

    click.secho(f"  ✓ OK", fg="green")

    # Push to cache if enabled
    if cache_config:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            shutil.copy(output_file, temp_path / f"{model_name}.3mf")
            shutil.copy(log_file, temp_path / f"{model_name}.log")

            push_files = [
                str(temp_path / f"{model_name}.3mf"),
                str(temp_path / f"{model_name}.log"),
            ]

            if oras_push(oci_ref, push_files, registry):
                click.echo(f"  ✓ Cached slice for {model_name}")
            else:
                click.echo(f"  ⚠ Failed to cache slice (continuing)")

            # Update latest tag on main branch
            if cache_config["is_main_branch"]:
                oci_latest = f"{oci_base}:latest"
                oras_push(oci_latest, push_files, registry)

    return True


@cli.command()
@click.option("--output-dir", type=click.Path(path_type=Path), default=Path("artifacts"))
@click.pass_context
def slice(ctx: click.Context, output_dir: Path) -> None:
    """Slice all rendered STL models to 3MF.

    Requires STL files to already be rendered in artifacts/stl/.
    Automatically uses GHCR caching when GITHUB_REPOSITORY is set.
    Models can be excluded in pyproject.toml [tool.scad-tools.slice.exclude].
    """
    orca_bin = find_orca_slicer()
    cache_config = get_cache_config()
    exclusions = get_slice_exclusions()

    if cache_config:
        click.echo(f"ORAS caching enabled: {cache_config['registry']}")

    # Find all STL files to slice
    stl_dir = output_dir / "stl"
    if not stl_dir.exists():
        click.secho("No STL files found. Run 'scad-tools render' first.", fg="red", err=True)
        sys.exit(1)

    stl_files = sorted(stl_dir.glob("*.stl"))
    if not stl_files:
        click.secho("No STL files found. Run 'scad-tools render' first.", fg="red", err=True)
        sys.exit(1)

    failed = []
    skipped = []
    sliced = 0

    for stl_file in stl_files:
        model_name = stl_file.stem

        # Check if excluded
        if model_name in exclusions:
            reason = exclusions[model_name]
            click.secho(f"Skipping {model_name}: {reason}", fg="yellow")
            skipped.append(model_name)
            continue

        if slice_single_model(model_name, output_dir, orca_bin, cache_config):
            sliced += 1
        else:
            failed.append(model_name)

    # Summary
    click.echo()
    if skipped:
        click.echo(f"Skipped {len(skipped)} model(s) (excluded in config)")
    if failed:
        click.secho(f"✗ {len(failed)} model(s) failed to slice", fg="red", err=True)
        for name in failed:
            click.echo(f"  - {name}")
        sys.exit(1)

    click.echo(f"✓ Sliced {sliced} model(s) to {output_dir / 'gcode'}")


if __name__ == "__main__":
    cli()
