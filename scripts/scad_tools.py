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
    uv run scad-tools toolchain install  # Install pinned OpenSCAD + OrcaSlicer

render, check, test, and slice run models in parallel; use -j N to limit.
Everything runs headless: no display or Xvfb needed (OpenSCAD renders PNG
previews offscreen; OrcaSlicer's CLI slices without one).

Environment variables for GHCR caching (auto-enabled in CI):
    GITHUB_REPOSITORY    - Owner/repo for cache (e.g., "owner/repo")
    GITHUB_TOKEN         - Token for GHCR authentication
    GITHUB_REF_NAME      - Branch name (updates 'latest' tag on main)
    SKIP_CACHE=1         - Disable caching
"""

import datetime
import functools
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import tomllib
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable, Iterable, TypeVar

import click
import oras.client

# Central exclusion patterns - the single source of truth
EXCLUDE_SUFFIXES = {
    "test": "_test.scad",       # Unit test files
    "constants": "_constants.scad",  # Shared constants
    "reference": "_reference.scad",  # Visualization-only models
    "lib": "_lib.scad",         # Shared library modules
}

# Bump to invalidate cached renders when render_single_model's OpenSCAD
# invocation changes in a way the model hash can't see (e.g. camera args).
RENDER_CACHE_VERSION = "1"

PREVIEW_ARGS = ["--autocenter", "--viewall", "--camera=0,0,0,55,0,25,500"]


def is_model_file(path: Path) -> bool:
    """True for printable models: .scad files without an excluded suffix."""
    return path.suffix == ".scad" and not path.name.endswith(
        tuple(EXCLUDE_SUFFIXES.values())
    )


def find_openscad() -> str:
    """
    Find OpenSCAD binary, checking platform-specific locations.

    Search order:
    1. macOS: Homebrew cask install location (openscad@snapshot, then openscad)
    2. PATH: 'openscad' command (`scad-tools toolchain install` links the
       pinned build into ~/.local/bin)
    """
    if sys.platform == "darwin":
        for cask in ("openscad@snapshot", "openscad"):
            try:
                result = subprocess.run(
                    ["brew", "info", "--cask", cask, "--json=v2"],
                    capture_output=True,
                    text=True,
                    check=True,
                )
                info = json.loads(result.stdout)
                for artifact in info["casks"][0].get("artifacts", []):
                    if isinstance(artifact, dict) and "app" in artifact:
                        openscad_bin = (
                            Path("/Applications") / artifact["app"][0] / "Contents/MacOS/OpenSCAD"
                        )
                        if openscad_bin.exists():
                            return str(openscad_bin)
            except (subprocess.CalledProcessError, FileNotFoundError, json.JSONDecodeError, KeyError, IndexError):
                pass

    # Fall back to PATH
    openscad = shutil.which("openscad")
    if openscad:
        return openscad

    raise click.ClickException(
        "OpenSCAD not found. Run `uv run scad-tools toolchain install` (Linux) or "
        "`brew install --cask openscad@snapshot` (macOS)."
    )


@functools.cache
def openscad_render_args(openscad: str) -> tuple[str, ...]:
    """
    Extra args for geometry/preview export.

    Builds with the Manifold backend (2024+) are 10-100x faster than CGAL and
    produce byte-identical output across runs; OpenSCAD 2021 lacks the flag.
    """
    result = subprocess.run([openscad, "--help"], capture_output=True, text=True)
    if "--backend" in result.stdout + result.stderr:
        return ("--backend=manifold",)
    return ()


def run_openscad(openscad: str, args: list[str]) -> subprocess.CompletedProcess:
    """Run OpenSCAD headlessly, capturing its output."""
    return subprocess.run([openscad] + args, capture_output=True, text=True)


def openscad_output(result: subprocess.CompletedProcess) -> str:
    """Combined OpenSCAD diagnostics, regardless of which stream they landed on."""
    return (result.stderr or "") + (result.stdout or "")


def openscad_diagnostics(result: subprocess.CompletedProcess, prefixes: tuple[str, ...]) -> list[str]:
    """Lines of OpenSCAD output starting with any of the given prefixes (e.g. 'ERROR:')."""
    return [line for line in openscad_output(result).splitlines() if line.startswith(prefixes)]


T = TypeVar("T")
R = TypeVar("R")


def run_parallel(func: Callable[[T], R], items: Iterable[T], jobs: int) -> list[R]:
    """Map func over items using up to `jobs` threads, preserving input order."""
    items = list(items)
    if jobs <= 1 or len(items) <= 1:
        return [func(item) for item in items]
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        return list(pool.map(func, items))


class TaskLog:
    """Buffers one task's output so parallel tasks print as contiguous blocks."""

    def __init__(self) -> None:
        self.lines: list[tuple[str, str | None, bool]] = []

    def echo(self, msg: str, fg: str | None = None, err: bool = False) -> None:
        self.lines.append((msg, fg, err))

    def flush(self) -> None:
        for msg, fg, err in self.lines:
            click.secho(msg, fg=fg, err=err)
        self.lines.clear()


_print_lock = threading.Lock()


def flush_log(log: TaskLog) -> None:
    """Print a task's buffered output atomically with respect to other tasks."""
    with _print_lock:
        log.flush()


def jobs_option(func):
    """Shared --jobs option for commands that process models in parallel."""
    return click.option(
        "--jobs", "-j",
        type=click.IntRange(min=1),
        default=lambda: os.cpu_count() or 1,
        show_default="CPU count",
        help="Number of models to process in parallel",
    )(func)


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


_INCLUDE_RE = re.compile(r"\b(?:include|use)\s*<([^>]+)>")
_COMMENT_RE = re.compile(r"//[^\n]*|/\*.*?\*/", re.DOTALL)


def find_scad_dependencies(scad_file: Path, _seen: set[Path] | None = None) -> list[Path]:
    """
    Find all files transitively included/used by a .scad file.

    Parses include <...> and use <...> statements (ignoring commented-out
    ones) and resolves paths relative to each including file's directory.
    Each dependency is visited once, so include cycles terminate.
    """
    seen = _seen if _seen is not None else {scad_file.resolve()}
    deps = []

    try:
        content = _COMMENT_RE.sub("", scad_file.read_text())
    except OSError:
        return deps

    for match in _INCLUDE_RE.finditer(content):
        dep_path = (scad_file.parent / match.group(1)).resolve()
        if dep_path in seen or not dep_path.is_file():
            continue
        seen.add(dep_path)
        deps.append(dep_path)
        deps.extend(find_scad_dependencies(dep_path, seen))

    return deps


def compute_model_hash(scad_file: Path) -> str:
    """
    Compute hash of a .scad file and all its dependencies.

    This ensures cache invalidation when any included file changes.
    """
    sha256 = hashlib.sha256()

    # Hash the render recipe, then the main file
    sha256.update(f"{RENDER_CACHE_VERSION}:{PREVIEW_ARGS}".encode())
    sha256.update(scad_file.read_bytes())

    # Hash all dependencies (sorted for determinism)
    deps = find_scad_dependencies(scad_file)
    for dep in sorted(set(deps)):
        sha256.update(dep.read_bytes())

    return sha256.hexdigest()


def compute_string_hash(s: str) -> str:
    """Compute SHA256 hash of a string."""
    return hashlib.sha256(s.encode()).hexdigest()


@functools.cache
def get_openscad_version(openscad: str) -> str:
    """Get OpenSCAD version string."""
    try:
        result = subprocess.run(
            [openscad, "--version"], capture_output=True, text=True
        )
        return result.stderr.strip() or result.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


@functools.cache
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
        # Layer titles are the files' basenames either way; pushing absolute
        # paths (instead of chdir-ing next to them) keeps this thread-safe.
        if files:
            abs_files = [str(Path(f).resolve()) for f in files]
            # Monolithic upload: GHCR rejects oras-py's chunked uploads (416)
            client.push(files=abs_files, target=oci_ref, disable_path_validation=True)
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
        if is_model_file(f):
            result.append(f)
            continue
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

        total_warnings += len(result.warnings)
        if not quiet:
            for warning in result.warnings:
                click.secho(str(warning), fg="yellow")

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
    log: TaskLog,
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

        log.echo(f"Checking cache for {out_name}...")

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
                log.echo(f"  ✓ Cache hit", fg="green")
                return True

        log.echo(f"  ✗ Cache miss, rendering...")

    # Render STL
    log.echo(f"Rendering {scad_file} -> {stl_file}")
    render_args = list(openscad_render_args(openscad))
    result = run_openscad(openscad, [*render_args, "-o", str(stl_file), str(scad_file)])
    if result.returncode != 0:
        log.echo(f"  ✗ STL render failed: {openscad_output(result)}", fg="red", err=True)
        return False

    # Render PNG preview
    log.echo(f"Rendering preview -> {png_file}")
    result = run_openscad(
        openscad,
        [*render_args, "-o", str(png_file), *PREVIEW_ARGS, str(scad_file)],
    )
    # OpenSCAD 2021 can't render offscreen: without a display it fails or
    # writes an empty PNG (sometimes exiting 0), so check the file itself
    if result.returncode != 0 or not png_file.exists() or png_file.stat().st_size == 0:
        png_file.unlink(missing_ok=True)
        log.echo(
            "  ⚠ Preview render produced no image (continuing). If this OpenSCAD "
            "can't render headless, run `uv run scad-tools toolchain install`.",
            fg="yellow",
        )

    log.echo(f"  ✓ OK", fg="green")

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
                log.echo(f"  ✓ Cached {out_name}")
            else:
                log.echo(f"  ⚠ Failed to cache (continuing)")

            # Update latest tag on main branch
            if cache_config["is_main_branch"]:
                oci_latest = f"{oci_base}:latest"
                oras_push(oci_latest, push_files, registry)

    return True


@cli.command()
@click.option("--output-dir", type=click.Path(path_type=Path), default=Path("artifacts"))
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@jobs_option
@click.pass_context
def render(ctx: click.Context, output_dir: Path, openscad: str | None, jobs: int) -> None:
    """Render all models to STL and PNG preview.

    Automatically uses GHCR caching when GITHUB_REPOSITORY is set.
    """
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path)
    cache_config = get_cache_config()

    if cache_config:
        click.echo(f"ORAS caching enabled: {cache_config['registry']}")
        get_openscad_version(openscad)  # warm the cache before threads race to fill it
    openscad_render_args(openscad)
    def render_one(f: Path) -> bool:
        log = TaskLog()
        ok = render_single_model(f, base_path, output_dir, openscad, cache_config, log)
        flush_log(log)
        return ok

    results = run_parallel(render_one, files, jobs)
    failed = [f for f, ok in zip(files, results) if not ok]

    if failed:
        click.echo(f"\n{len(failed)} file(s) failed to render", err=True)
        for f in failed:
            click.echo(f"  - {f}", err=True)
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

    # Output names derive from the path under base_path, so normalize to that
    if not file.resolve().is_relative_to(base_path.resolve()):
        raise click.ClickException(f"{file} is not under {base_path}")
    file = base_path / file.resolve().relative_to(base_path.resolve())

    log = TaskLog()
    ok = render_single_model(file, base_path, output_dir, openscad, None, log)
    log.flush()
    if not ok:
        sys.exit(1)


@cli.command()
@click.argument("file", type=click.Path(exists=True, path_type=Path))
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
def gui(file: Path, openscad: str | None) -> None:
    """Open a file in OpenSCAD GUI."""
    openscad = openscad or find_openscad()
    subprocess.Popen([openscad, str(file)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    click.echo(f"Opened {file} in OpenSCAD")


def evaluate_scad(openscad: str, scad_file: Path, hard_warnings: bool) -> subprocess.CompletedProcess:
    """Evaluate a .scad file to CSG (fast; no CGAL render, no display needed)."""
    args = ["--hardwarnings"] if hard_warnings else []
    return run_openscad(openscad, [*args, "--export-format", "csg", "-o", os.devnull, str(scad_file)])


@cli.command()
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@jobs_option
@click.pass_context
def check(ctx: click.Context, openscad: str | None, jobs: int) -> None:
    """Validate all models evaluate without errors."""
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path)

    def check_one(f: Path) -> bool:
        log = TaskLog()
        log.echo(f"Checking {f}...")
        result = evaluate_scad(openscad, f, hard_warnings=False)
        # OpenSCAD 2021 exits 0 on many errors (e.g. failed asserts), so also scan output
        errors = openscad_diagnostics(result, ("ERROR:",))
        ok = result.returncode == 0 and not errors
        for line in errors:
            log.echo(f"  {line}", fg="red")
        log.echo("  ✓ OK" if ok else "  ✗ FAILED", fg=None if ok else "red")
        flush_log(log)
        return ok

    results = run_parallel(check_one, files, jobs)
    failed = [f for f, ok in zip(files, results) if not ok]

    if failed:
        click.echo(f"\n{len(failed)} file(s) failed validation", err=True)
        sys.exit(1)

    click.echo(f"\n✓ All {len(files)} model(s) validated successfully")


@cli.command()
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@jobs_option
@click.pass_context
def test(ctx: click.Context, openscad: str | None, jobs: int) -> None:
    """Run OpenSCAD unit tests.

    A test fails if OpenSCAD exits non-zero or reports any ERROR or WARNING
    (failed assert(), undefined variables, etc.).
    """
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path, only_tests=True)

    if not files:
        click.echo(f"No test files found in {base_path}")
        sys.exit(0)

    def test_one(f: Path) -> bool:
        log = TaskLog()
        log.echo(f"Running {f}...")
        result = evaluate_scad(openscad, f, hard_warnings=True)

        # Print ECHO output for visibility, and errors/warnings for diagnosis
        for line in openscad_diagnostics(result, ("ECHO:",)):
            log.echo(f"  {line}")
        problems = openscad_diagnostics(result, ("ERROR:", "WARNING:"))
        for line in problems:
            log.echo(f"  {line}", fg="red")

        ok = False
        if result.returncode != 0:
            log.echo(f"  ✗ FAILED (exit code {result.returncode})", fg="red")
        elif problems:
            log.echo("  ✗ FAILED", fg="red")
        else:
            log.echo("  ✓ PASSED")
            ok = True
        flush_log(log)
        return ok

    results = run_parallel(test_one, files, jobs)
    failed = [f for f, ok in zip(files, results) if not ok]

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
        "OrcaSlicer not found. Run `uv run scad-tools toolchain install orcaslicer` (Linux) "
        "or install from https://github.com/OrcaSlicer/OrcaSlicer/releases"
    )


@functools.cache
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
    """
    Run the OrcaSlicer CLI. It slices without a display; only the 3MF plate
    thumbnail needs OpenGL, and it skips that (as it also did under Xvfb), so
    slice_single_model injects one afterwards (see inject_3mf_thumbnail).

    Runs in a scratch directory because the CLI drops a result.json into its
    working directory, which parallel slices would otherwise all overwrite.
    Paths in args must therefore be absolute.
    """
    with tempfile.TemporaryDirectory() as scratch:
        return subprocess.run([orca_bin] + args, capture_output=True, text=True, cwd=scratch)


# Bump to invalidate cached slices when slice_single_model's output changes in
# a way the cache tag can't see (e.g. post-processing of the exported 3MF).
SLICE_CACHE_VERSION = "1"

# Plate thumbnail entries as OrcaSlicer's GUI writes them (v2.3.1,
# src/libslic3r/Format/bbs_3mf.{hpp,cpp}): THUMBNAIL_FILE_FORMAT
# "Metadata/plate_%1%.png" plus a "_small" variant from
# _add_thumbnail_file_to_archive. The CLI's _rels/.rels already points at both
# (thumbnail, cover-thumbnail-middle, cover-thumbnail-small), and
# [Content_Types].xml already has the png Default; only the files are missing.
PLATE_THUMBNAIL = "Metadata/plate_1.png"
PLATE_THUMBNAIL_SMALL = "Metadata/plate_1_small.png"
MODEL_SETTINGS_CONFIG = "Metadata/model_settings.config"
_GCODE_FILE_META_RE = re.compile(
    r'^([ \t]*)<metadata key="gcode_file" value="Metadata/plate_1\.gcode"/>\n', re.MULTILINE
)


def inject_3mf_thumbnail(threemf: Path, png: Path) -> bool:
    """
    Add a plate thumbnail to a single-plate 3MF that OrcaSlicer's headless CLI
    exported without one, mirroring what its GUI exporter writes:

    - Metadata/plate_1.png and Metadata/plate_1_small.png, stored uncompressed
      (the exporter uses MZ_NO_COMPRESSION for thumbnails). The GUI downsamples
      the small one to 128x128; here both are the same 512x512 PNG, since
      OrcaSlicer never checks its size and resizing would need an image library.
    - <metadata key="thumbnail_file" value="Metadata/plate_1.png"/> in the
      plate section of Metadata/model_settings.config, right after gcode_file,
      as _add_model_config_file_to_archive writes it.

    Every other entry (including the gcode and its .md5) keeps its bytes and
    compression method. The archive is rewritten to a temp file and swapped in,
    so a failure leaves the original intact. Returns False if the 3MF already
    has a plate thumbnail.
    """
    thumbnail = png.read_bytes()
    tmp = threemf.with_name(threemf.name + ".tmp")
    try:
        with zipfile.ZipFile(threemf) as src, zipfile.ZipFile(tmp, "w") as dst:
            if PLATE_THUMBNAIL in src.namelist():
                return False

            def add_thumbnails(date_time: tuple) -> None:
                for name in (PLATE_THUMBNAIL, PLATE_THUMBNAIL_SMALL):
                    entry = zipfile.ZipInfo(name, date_time=date_time)
                    dst.writestr(entry, thumbnail, compress_type=zipfile.ZIP_STORED)

            added = False
            for info in src.infolist():
                data = src.read(info)
                if info.filename == MODEL_SETTINGS_CONFIG:
                    text = data.decode()
                    if 'key="thumbnail_file"' not in text:
                        text, n = _GCODE_FILE_META_RE.subn(
                            lambda m: m.group(0)
                            + f'{m.group(1)}<metadata key="thumbnail_file" value="{PLATE_THUMBNAIL}"/>\n',
                            text,
                            count=1,
                        )
                        if n != 1:
                            raise ValueError(f"no plate 1 gcode_file entry in {MODEL_SETTINGS_CONFIG}")
                    data = text.encode()
                dst.writestr(info, data, compress_type=info.compress_type)
                # The GUI writes thumbnails right after [Content_Types].xml.
                if info.filename == "[Content_Types].xml":
                    add_thumbnails(info.date_time)
                    added = True
            if not added:
                add_thumbnails(datetime.datetime.now().timetuple()[:6])
        os.replace(tmp, threemf)
    finally:
        tmp.unlink(missing_ok=True)
    return True


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
    log: TaskLog,
) -> bool:
    """
    Slice a single STL model to 3MF, with optional caching.

    Args:
        model_name: Output name (e.g., "rack__retention_bracket")
        artifacts_dir: Directory containing stl/ (and preview/ for the 3MF
            thumbnail), and for gcode/ output
        orca_bin: Path to OrcaSlicer binary
        cache_config: ORAS cache configuration or None
        log: Buffer for this model's output

    Returns True on success, False on failure.
    """
    stl_file = artifacts_dir / "stl" / f"{model_name}.stl"
    gcode_dir = artifacts_dir / "gcode"
    logs_dir = artifacts_dir / "logs"
    gcode_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    output_file = gcode_dir / f"{model_name}.3mf"
    log_file = logs_dir / f"{model_name}.log"
    preview_file = artifacts_dir / "preview" / f"{model_name}.png"

    if not stl_file.exists():
        log.echo(f"  ✗ STL not found: {stl_file}", fg="red", err=True)
        return False

    # Extract project/model from name (e.g., "rack__model" -> "rack/model")
    model_path = model_name.replace("__", "/")

    # Check cache if enabled
    if cache_config:
        stl_hash = compute_file_hash(stl_file)
        profiles_hash = compute_profiles_hash()[:8]
        slicer_hash = compute_string_hash(get_orca_version(orca_bin))[:8]
        # The preview is embedded as the plate thumbnail, so it's part of the key.
        preview_hash = compute_file_hash(preview_file) if preview_file.exists() else "no-preview"
        recipe_hash = compute_string_hash(f"{SLICE_CACHE_VERSION}:{preview_hash}")[:8]
        cache_tag = f"{slicer_hash}-{profiles_hash}-{stl_hash[:12]}-{recipe_hash}"

        registry = cache_config["registry"]
        oci_base = (
            f"{registry}/{cache_config['repo_owner']}/"
            f"{cache_config['repo_name']}/slices/{model_path}"
        )
        oci_ref = f"{oci_base}:{cache_tag}"

        log.echo(f"Checking slice cache for {model_name}...")

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
                log.echo(f"  ✓ Cache hit", fg="green")
                return True

        log.echo(f"  ✗ Cache miss, slicing...")

    # Build settings argument: machine;process;filament
    settings = ";".join(
        str(p.resolve()) for p in (ORCA_MACHINE_PROFILE, ORCA_PROCESS_PROFILE, ORCA_FILAMENT_PROFILE)
    )

    # Make paths absolute for OrcaSlicer
    abs_input = stl_file.resolve()
    abs_output = output_file.resolve()

    log.echo(f"Slicing {model_name}...")
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
        log.echo(f"  ✗ Slicing failed", fg="red", err=True)
        if log_content:
            for line in log_content.splitlines()[-5:]:
                log.echo(f"    {line}")
        return False

    log.echo(f"  ✓ OK", fg="green")

    # The headless CLI can't render a plate thumbnail (no OpenGL), so Bambu
    # printers/apps would show no preview; embed the OpenSCAD render instead.
    if not preview_file.exists():
        log.echo(f"  - No preview at {preview_file}, 3MF left without a thumbnail")
    else:
        try:
            if inject_3mf_thumbnail(output_file, preview_file):
                log.echo(f"  ✓ Embedded thumbnail from {preview_file.name}")
        except (OSError, ValueError, zipfile.BadZipFile) as e:
            log.echo(f"  ⚠ Failed to embed thumbnail (continuing): {e}", fg="yellow")

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
                log.echo(f"  ✓ Cached slice for {model_name}")
            else:
                log.echo(f"  ⚠ Failed to cache slice (continuing)")

            # Update latest tag on main branch
            if cache_config["is_main_branch"]:
                oci_latest = f"{oci_base}:latest"
                oras_push(oci_latest, push_files, registry)

    return True


@cli.command()
@click.option("--output-dir", type=click.Path(path_type=Path), default=Path("artifacts"))
@jobs_option
@click.pass_context
def slice(ctx: click.Context, output_dir: Path, jobs: int) -> None:
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

    to_slice = []
    skipped = []
    for stl_file in stl_files:
        model_name = stl_file.stem
        if model_name in exclusions:
            click.secho(f"Skipping {model_name}: {exclusions[model_name]}", fg="yellow")
            skipped.append(model_name)
        else:
            to_slice.append(model_name)

    if cache_config:
        get_orca_version(orca_bin)  # warm the cache before threads race to fill it

    def slice_one(model_name: str) -> bool:
        log = TaskLog()
        ok = slice_single_model(model_name, output_dir, orca_bin, cache_config, log)
        flush_log(log)
        return ok

    results = run_parallel(slice_one, to_slice, jobs)
    failed = [name for name, ok in zip(to_slice, results) if not ok]
    sliced = len(to_slice) - len(failed)

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


# =============================================================================
# Static Gallery Site
# =============================================================================


def humanize_name(name: str) -> str:
    """Turn a basename like 'apple_tv_retention_bracket' into 'Apple Tv Retention Bracket'."""
    return name.replace("_", " ").strip().title()


def extract_model_metadata(scad_file: Path) -> tuple[str, str]:
    """
    Extract a display title and short description from a .scad file's header comment.

    The first non-empty leading '//' comment line becomes the title. The first
    paragraph after it (until a blank comment line) becomes the description.
    Customizer directive comments (e.g. 'preview[...]') are ignored. Falls back
    to a humanized file name when no header comment is present.
    """
    title = None
    desc_lines: list[str] = []
    seen_title = False

    for line in scad_file.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("//"):
            text = stripped[2:].strip()
            if text.startswith("preview[") or text.startswith("["):
                continue
            if not text:
                # Blank comment line: ends the description paragraph once started
                if seen_title and desc_lines:
                    break
                continue
            if title is None:
                title = text
                seen_title = True
            else:
                desc_lines.append(text)
        elif not stripped:
            continue
        else:
            # Hit code (or a block comment) — header is done
            break

    if not title:
        title = humanize_name(scad_file.stem)
    return title, " ".join(desc_lines)


def build_manifest(base_path: Path, artifacts_dir: Path) -> dict:
    """Build the gallery manifest from rendered artifacts and source metadata."""
    stl_dir = artifacts_dir / "stl"
    preview_dir = artifacts_dir / "preview"
    repo = os.environ.get("GITHUB_REPOSITORY")
    ref = os.environ.get("GITHUB_REF_NAME", "main")

    models = []
    for scad_file in find_scad_files(base_path):
        out_name = get_output_name(scad_file, base_path)
        stl_file = stl_dir / f"{out_name}.stl"
        if not stl_file.exists():
            continue  # only include models that actually rendered

        rel_path = scad_file.relative_to(base_path)
        project = str(rel_path.parent)
        title, description = extract_model_metadata(scad_file)

        entry = {
            "name": out_name,
            "title": title,
            "description": description,
            "project": project,
            "model": scad_file.stem,
            "stl": f"models/{out_name}.stl",
        }

        png_file = preview_dir / f"{out_name}.png"
        if png_file.exists():
            entry["preview"] = f"previews/{out_name}.png"
        if repo:
            entry["source"] = (
                f"https://github.com/{repo}/blob/{ref}/{base_path}/{rel_path}"
            )

        models.append(entry)

    return {
        "generated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "repo": repo,
        "models": models,
    }


@cli.command()
@click.option(
    "--artifacts-dir",
    type=click.Path(path_type=Path),
    default=Path("artifacts"),
    help="Directory containing rendered stl/ and preview/ output",
)
@click.option(
    "--site-src",
    type=click.Path(path_type=Path),
    default=Path("site"),
    help="Static frontend template directory",
)
@click.option(
    "--output-dir",
    type=click.Path(path_type=Path),
    default=Path("_site"),
    help="Output directory for the built site (Pages artifact root)",
)
@click.pass_context
def gallery(
    ctx: click.Context, artifacts_dir: Path, site_src: Path, output_dir: Path
) -> None:
    """Build the static three.js gallery site from rendered artifacts.

    Copies the frontend template, the rendered STL/PNG files, and a generated
    manifest.json into the output directory, ready to deploy to GitHub Pages.
    Run `scad-tools render` first to populate the artifacts directory.
    """
    base_path = ctx.obj["base_path"]

    if not site_src.exists():
        raise click.ClickException(f"Site template not found: {site_src}")

    # Fresh output directory
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    # Copy static frontend (index.html, app.js, style.css, …)
    for item in site_src.iterdir():
        if item.is_file():
            shutil.copy(item, output_dir / item.name)
        elif item.is_dir():
            shutil.copytree(item, output_dir / item.name)

    # Build manifest and copy referenced assets
    manifest = build_manifest(base_path, artifacts_dir)
    models_out = output_dir / "models"
    previews_out = output_dir / "previews"
    models_out.mkdir(exist_ok=True)
    previews_out.mkdir(exist_ok=True)

    stl_dir = artifacts_dir / "stl"
    preview_dir = artifacts_dir / "preview"
    for entry in manifest["models"]:
        shutil.copy(stl_dir / f"{entry['name']}.stl", models_out / f"{entry['name']}.stl")
        if "preview" in entry:
            shutil.copy(
                preview_dir / f"{entry['name']}.png",
                previews_out / f"{entry['name']}.png",
            )

    (output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))

    # A .nojekyll file keeps GitHub Pages from mangling the static assets
    (output_dir / ".nojekyll").write_text("")

    count = len(manifest["models"])
    click.secho(f"✓ Built gallery with {count} model(s) -> {output_dir}", fg="green")
    if count == 0:
        click.secho(
            "  (no STL artifacts found — run 'scad-tools render' first)", fg="yellow"
        )


from scripts.toolchain import toolchain  # noqa: E402  (imports helpers above)

cli.add_command(toolchain)


if __name__ == "__main__":
    cli()
