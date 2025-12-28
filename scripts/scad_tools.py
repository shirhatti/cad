#!/usr/bin/env python3
"""
Unified OpenSCAD tooling CLI.

Single source of truth for file discovery, rendering, linting, and other operations.
Replaces scattered find commands in justfile and CI with consistent exclusion logic.

Usage:
    uv run scad-tools list          # List renderable models
    uv run scad-tools list --tests  # List test files
    uv run scad-tools lint          # Lint all models
    uv run scad-tools render        # Render all models
    uv run scad-tools check         # Validate models render
    uv run scad-tools test          # Run unit tests
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

import click

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


@cli.command()
@click.option("--tests", is_flag=True, help="List only test files")
@click.option("--libs", is_flag=True, help="Include library files")
@click.option("--all", "include_all", is_flag=True, help="Include all file types")
@click.option("--output-names", is_flag=True, help="Show output names instead of paths")
@click.option("--null", "-0", is_flag=True, help="Null-separated output (for xargs -0)")
@click.pass_context
def list(
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

    # ANSI colors
    if sys.stdout.isatty():
        RED, YELLOW, GREEN, RESET = "\033[91m", "\033[93m", "\033[92m", "\033[0m"
    else:
        RED, YELLOW, GREEN, RESET = "", "", "", ""

    total_errors = 0
    total_warnings = 0
    failed = 0

    for f in files:
        result = lint_file(f)

        for error in result.errors:
            click.echo(f"{RED}{error}{RESET}")
            total_errors += 1

        if not quiet:
            for warning in result.warnings:
                click.echo(f"{YELLOW}{warning}{RESET}")
                total_warnings += 1

        if not result.passed or (strict and result.warnings):
            failed += 1

    # Summary
    click.echo()
    passed = len(files) - failed
    if failed == 0:
        click.echo(f"{GREEN}All {len(files)} file(s) passed Customizer linting{RESET}")
    else:
        click.echo(f"{RED}{failed} file(s) failed, {passed} passed{RESET}")
        click.echo(f"  {total_errors} error(s), {total_warnings} warning(s)")

    if strict:
        sys.exit(1 if (total_errors + total_warnings) > 0 else 0)
    sys.exit(1 if total_errors > 0 else 0)


@cli.command()
@click.option("--output-dir", type=click.Path(path_type=Path), default=Path("artifacts"))
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@click.option("--xvfb", is_flag=True, help="Run under xvfb-run")
@click.pass_context
def render(ctx: click.Context, output_dir: Path, openscad: str | None, xvfb: bool) -> None:
    """Render all models to STL."""
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path)

    stl_dir = output_dir / "stl"
    stl_dir.mkdir(parents=True, exist_ok=True)

    failed = []
    for f in files:
        out_name = get_output_name(f, base_path)
        out_file = stl_dir / f"{out_name}.stl"

        click.echo(f"Rendering {f} -> {out_file}")

        cmd = [openscad, "-o", str(out_file), str(f)]
        if xvfb:
            cmd = ["xvfb-run", "--auto-servernum"] + cmd

        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            click.echo(f"  ✗ FAILED: {result.stderr}", err=True)
            failed.append(f)
        else:
            click.echo(f"  ✓ OK")

    if failed:
        click.echo(f"\n{len(failed)} file(s) failed to render", err=True)
        sys.exit(1)

    click.echo(f"\n✓ Rendered {len(files)} model(s) to {stl_dir}")


@cli.command()
@click.option("--openscad", default=None, help="OpenSCAD binary path (auto-detected if not set)")
@click.option("--xvfb", is_flag=True, help="Run under xvfb-run")
@click.pass_context
def check(ctx: click.Context, openscad: str | None, xvfb: bool) -> None:
    """Validate all models render without errors."""
    base_path = ctx.obj["base_path"]
    openscad = openscad or find_openscad()
    files = find_scad_files(base_path)

    failed = []
    for f in files:
        click.echo(f"Checking {f}...")

        cmd = [openscad, "--export-format", "csg", "-o", "/dev/null", str(f)]
        if xvfb:
            cmd = ["xvfb-run", "--auto-servernum"] + cmd

        result = subprocess.run(cmd, capture_output=True, text=True)
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
@click.option("--xvfb", is_flag=True, help="Run under xvfb-run")
@click.pass_context
def test(ctx: click.Context, openscad: str | None, xvfb: bool) -> None:
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

        cmd = [openscad, "--hardwarnings", "-o", "/dev/null", "--export-format", "csg", str(f)]
        if xvfb:
            cmd = ["xvfb-run", "--auto-servernum"] + cmd

        result = subprocess.run(cmd, capture_output=True, text=True)

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


if __name__ == "__main__":
    cli()
