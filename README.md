# CAD Projects

Personal CAD projects designed with OpenSCAD and sliced with Orca Slicer.

![CI Status](https://github.com/shirhatti/cad/workflows/CI/badge.svg)

## Projects

Each project is in its own subdirectory under `projects/`:

- [rack](./projects/rack/) - 1U rack shelf device mounts (Apple TV mount, retention strap, WiiM Amp bracket)

## Quick Start

```bash
git clone https://github.com/shirhatti/cad.git
cd cad

# Slicing needs the OrcaSlicer profiles from the .orca-slicer submodule. This
# fetches only resources/profiles at the pinned commit (as CI does), instead
# of the whole OrcaSlicer source tree that `git submodule update --init` clones.
uv run scad-tools profiles fetch

# Optional: Enter Nix development environment
nix develop

# Install dependencies and pre-commit hooks
just setup

# Linux: install the pinned OpenSCAD + OrcaSlicer (headless, no display needed)
just toolchain
# macOS: brew install --cask openscad@snapshot

# Lint, test, and validate all models
just lint
just test
just check

# Render all models to STL + PNG previews
just build

# Mesh checks, then slice to 3MF (verifies slicer settings and print budgets)
just mesh
just slice

# Or all of it, updating print-metrics.json
just snapshot

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

### Print checks
- `just mesh` - Mesh checks on rendered STLs (watertight, part count, plate fit, walls, overhangs)
- `just slice` - Slice all rendered STL files to 3MF, verifying slicer settings and print budgets
- `just snapshot` - Render, check, and slice everything, then update `print-metrics.json`
- `just metrics-diff` - Show print-metric changes against the committed snapshot
- `just profiles` - Fetch the pinned OrcaSlicer profiles
- `just profiles-lint` - Lint the slicer profiles and local overrides

### Watching for changes
- `just watch` - Auto-rebuild all files on changes
- `just watch-file <file>` - Auto-rebuild a specific file

## Workflow

1. Create a project directory in `projects/<project-name>/`
2. Add `.scad` files and a project README
3. Declare what you expect of the print in `pyproject.toml` (see below)
4. Run `just snapshot` to render, check, and slice, then commit the updated
   `print-metrics.json` with your change

## Print checks

Think of the pipeline as a compiler, with a check at each stage:

| Stage | Command | Checks |
|---|---|---|
| `.scad` source | `just lint`, `just test` | Customizer compliance; `assert()`-based unit tests |
| STL mesh | `just mesh` | Watertight, part count, fits the build volume, thinnest wall, overhang area, bed contact |
| Slicer profiles | `just profiles-lint` | Inheritance resolves; no typo'd or no-op overrides |
| Sliced 3MF | `just slice` | The slicer applied every profile setting; print time, filament, supports, unsupported bridge spans |

**Expectations** are per-model rules in `pyproject.toml`, like type
annotations for a print. Defaults apply to every model:

```toml
[tool.scad-tools.expect.defaults]
watertight = true
bodies = 1
min_wall_mm = 0.8      # two 0.4 mm perimeters
max_bridge_mm = 25     # longest span over air

[tool.scad-tools.expect.models."rack/apple_tv_retention_bracket.scad"]
max_time = "2h20m"
max_filament_g = 62
```

Mesh rules: `watertight`, `bodies`, `fits_plate`, `min_wall_mm`,
`max_overhang_mm2`, `min_bed_contact_mm2`. Slice rules: `max_time`,
`max_filament_g`, `supports`, `max_support_pct`, `max_bridge_mm` (the longest
stretch of bridge line with nothing printed beneath it, so a bridge over support
or along a narrow channel doesn't count), `max_overhang_wall_pct`. Unknown keys are errors, so a typo can't silently
switch a check off.

**`print-metrics.json`** is a committed snapshot of every model's metrics: print
time, filament, layers, support share, size, thinnest wall, and so on. A PR
that changes a model shows the effect in its diff, and CI comments a table of
changes against the base branch. CI fails if the snapshot is stale, the same
way it would for an out-of-date lockfile. Slicer estimates jitter slightly
between identical runs, so time, filament and support share compare within
about 2%.

## Orca Slicer Configuration

Printer profiles come from the `.orca-slicer` git submodule (OrcaSlicer upstream,
pinned to the release tag matching the OrcaSlicer version in `toolchain.toml`),
with local overrides in `.orca-profiles-local/`. Default settings:
- **Printer**: Bambu Lab A1 (0.4mm nozzle)
- **Process**: 0.20mm Standard layer height
- **Filament**: Generic PLA

To change settings, edit the profile path constants in `scripts/profiles.py`:
```python
ORCA_MACHINE_PROFILE = ORCA_PROFILES_LOCAL / "machine/Bambu Lab A1 0.4 nozzle.json"
ORCA_PROCESS_PROFILE = ORCA_PROFILES_LOCAL / "process/0.20mm Standard @BBL A1.json"
ORCA_FILAMENT_PROFILE = ORCA_PROFILES_UPSTREAM / "filament/Generic PLA @BBL A1.json"
```

The OrcaSlicer CLI doesn't resolve profile inheritance, so `scad-tools slice`
flattens each profile into a complete config (kept in `artifacts/profiles/`;
`uv run scad-tools profiles show <machine|process|filament>` prints one). It
then checks that the 3MF records exactly those settings.

A model that needs different slicer settings gets them in `pyproject.toml`,
layered on top of the shared profiles:

```toml
[tool.scad-tools.slice.settings."binder/dual_phone_case.scad"]
enable_support = false  # print-in-place hinge: support in the knuckles would fuse it
```

Any machine, process, or filament setting works (`uv run scad-tools profiles
show process` lists them). A setting no profile defines is an error, so a typo
can't slice with the setting silently unchanged. The model gets its own
flattened profile set in `artifacts/profiles/<model>/`, the post-slice check
confirms the slicer applied the override, and `print-metrics.json` records it.

Models that can't be sliced are excluded in `pyproject.toml` under
`[tool.scad-tools.slice.exclude]`.

See `.orca-profiles-local/README.md` for details on profile overrides.

## Continuous Integration

GitHub Actions runs on every branch push and pull request (superseded runs are
cancelled), in this order:

1. **Lint** - MakerBot Customizer compliance (`scad-tools lint`) and slicer profiles (`scad-tools profiles lint`)
2. **Test** - OpenSCAD unit tests (`*_test.scad`)
3. **Check** - Validates all models render without errors
4. **Render** - Generates STL + PNG from all `.scad` models
5. **Mesh** - Mesh checks and expectations on the STLs
6. **Slice** - Generates 3MF files with embedded G-code, verifies settings and expectations
7. **Print metrics** - Posts a table of metric changes to the job summary (and as a PR comment), then fails if `print-metrics.json` is stale

Renders and slices are cached in GHCR, keyed by a content hash of each model
and its dependencies.

CI runs inside a prebuilt container image (`ci/Dockerfile`) holding the
OpenSCAD and OrcaSlicer builds pinned in `toolchain.toml`, so it needs no apt
installs, downloads, or virtual display. The image is tagged by a hash of
those two files and rebuilt only when they change.

Build artifacts (STL, PNG, 3MF, logs) are uploaded and available for download from the Actions tab.

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
