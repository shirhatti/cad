# CAD Projects

Personal CAD projects designed with OpenSCAD and sliced with Orca Slicer.

![CI Status](https://github.com/shirhatti/cad/workflows/CI/badge.svg)

## Projects

Each project is in its own subdirectory under `projects/`:

- [rack](./projects/rack/) - 1U rack shelf device mounts (Apple TV mount, retention strap, WiiM Amp bracket)

## Quick Start

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/shirhatti/cad.git
cd cad

# Or initialize submodules after cloning
git submodule update --init --depth 1

# Optional: Enter Nix development environment
nix develop

# Install dependencies and pre-commit hooks
just setup

# Lint, test, and validate all models
just lint
just test
just check

# Render all models to STL + PNG previews
just build

# Slice all rendered STL files to 3MF
just slice

# Render a single file (pass a path)
just render projects/rack/apple_tv_retention_bracket.scad
```

All commands are thin wrappers around the unified `scad-tools` CLI
(`scripts/scad_tools.py`). Run `uv run scad-tools --help` to see it directly.

## Commands

### Quality checks
- `just lint` - Lint all models for MakerBot Customizer compliance
- `just lint-strict` - Lint with warnings treated as errors
- `just test` - Run OpenSCAD unit tests (`*_test.scad`)
- `just check` - Validate all models render without errors
- `just pre-commit` - Run all pre-commit hooks

### OpenSCAD rendering
- `just build` - Render all `.scad` models to STL + PNG preview
- `just render <file>` - Render a single file (pass a path)
- `just gui <file>` - Open a file in the OpenSCAD GUI
- `just clean` - Remove build artifacts (`artifacts/`)

### Orca Slicer (3MF/G-code generation)
- `just slice` - Slice all rendered STL files to 3MF with embedded G-code

### Watching for changes
- `just watch` - Auto-rebuild all files on changes
- `just watch-file <file>` - Auto-rebuild a specific file

## Workflow

1. Create a project directory in `projects/<project-name>/`
2. Add `.scad` files and a project README
3. Run `just build` to render STL files
4. Run `just slice` to generate 3MF/G-code for all rendered models

## Orca Slicer Configuration

Printer profiles are loaded from the `.orca-slicer` git submodule (OrcaSlicer upstream). Default settings:
- **Printer**: Bambu Lab A1 (0.4mm nozzle)
- **Process**: 0.20mm Standard layer height
- **Filament**: Generic PLA

To change settings, edit the profile path constants near the top of the
OrcaSlicer section in `scripts/scad_tools.py`:
```python
ORCA_MACHINE_PROFILE = ORCA_PROFILES_LOCAL / "machine/Bambu Lab A1 0.4 nozzle.json"
ORCA_PROCESS_PROFILE = ORCA_PROFILES_LOCAL / "process/0.20mm Standard @BBL A1.json"
ORCA_FILAMENT_PROFILE = ORCA_PROFILES_UPSTREAM / "filament/Generic PLA @BBL A1.json"
```

Models that can't be sliced (e.g. too large for the build plate) are excluded
in `pyproject.toml` under `[tool.scad-tools.slice.exclude]`.

See `.orca-profiles-local/README.md` for details on profile overrides.

## Continuous Integration

GitHub Actions automatically validates all models on every push:

1. **Syntax Check** - Validates OpenSCAD syntax
2. **Rendering** - Generates STL files from all `.scad` models
3. **Slicing** - Generates 3MF files with embedded G-code
4. **Validation** - Ensures no slicing errors occurred

Build artifacts (STL, 3MF, logs) are uploaded and available for download from the Actions tab.

## Model Gallery (GitHub Pages)

An interactive gallery lets you explore every model in the browser with a
[three.js](https://threejs.org/) STL viewer — orbit, zoom, wireframe, and
auto-rotate, with per-model info pulled from each `.scad` header comment.

🔗 **<https://shirhatti.github.io/cad/>**

The `Deploy Gallery to Pages` workflow (`.github/workflows/pages.yml`) runs
**after CI completes on `main`** (and on demand via *Run workflow*). Sequencing
it after CI means the GHCR render cache is already warm, so the gallery build
gets cache hits — it downloads the prebuilt STL/PNG instead of re-rendering, and
the two workflows never race for the same cache. It then builds the static site
and publishes it to Pages.

> **One-time setup:** in **Settings → Pages**, set *Source* to **GitHub
> Actions**. The first deploy populates the site.

### Building the gallery locally

```bash
just gallery-build      # render all models + build the site into _site/
just serve-gallery      # serve _site/ at http://localhost:8000
```

`just gallery` builds the site from whatever is already in `artifacts/`, while
`scad-tools gallery` is the underlying command (frontend template lives in
`site/`, output goes to `_site/`).

## Adding New Projects

1. Create a new directory: `projects/<project-name>/`
2. Add your `.scad` files
3. Add a `README.md` describing the project
4. Commit and push - CI will automatically validate

Files are named `<project-name>__<model-name>.stl` in artifacts to avoid conflicts.
