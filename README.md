# CAD Projects

Personal CAD projects designed with OpenSCAD and sliced with Orca Slicer.

![CI Status](https://github.com/shirhatti/cad/workflows/CI/badge.svg)

## Projects

Each project is in its own subdirectory under `projects/`:

- [rack-shelf-apple-tv-mount](./projects/rack-shelf-apple-tv-mount/) - Mount for Apple TV on 1U rack shelf

## Quick Start

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/shirhatti/cad.git
cd cad

# Or initialize submodules after cloning
git submodule update --init --depth 1

# Optional: Enter Nix development environment
nix develop

# Build all projects
just build

# Check syntax
just check

# Render and slice specific project
just render rack-shelf-apple-tv-mount__rack_shelf_apple_tv_mount
just slice rack-shelf-apple-tv-mount__rack_shelf_apple_tv_mount
```

## Commands

### OpenSCAD Rendering
- `just build` - Render all `.scad` files to STL
- `just render <name>` - Render a specific file with timestamp
- `just gui <name>` - Open file in OpenSCAD GUI
- `just preview <name>` - Generate PNG preview
- `just check` - Syntax check all files
- `just clean` - Remove build artifacts

### Orca Slicer (3MF/G-code generation)
- `just slice <name>` - Slice STL to 3MF with embedded G-code
- `just open-slice <name>` - Open sliced 3MF in Orca Slicer
- `just prepare <name>` - Full workflow: render → slice → open

### Watching for Changes
- `just watch` - Auto-rebuild all files on changes
- `just watch-file <name>` - Auto-rebuild specific file

## Workflow

1. Create project directory in `projects/<project-name>/`
2. Add `.scad` files and project README
3. Run `just build` to render STL files
4. Run `just slice <project>__<model>` to generate G-code

## Orca Slicer Configuration

Printer profiles are loaded from the `.orca-slicer` git submodule (OrcaSlicer upstream). Default settings:
- **Printer**: Bambu Lab A1 (0.4mm nozzle)
- **Process**: 0.20mm Standard layer height
- **Filament**: Generic PLA

To change settings, edit variables in `justfile`:
```just
_orca_machine_profile := ".orca-profiles-local/BBL/machine/..."
_orca_process_profile := ".orca-slicer/resources/profiles/BBL/process/..."
_orca_filament_profile := ".orca-slicer/resources/profiles/BBL/filament/..."
```

See `.orca-profiles-local/README.md` for details on profile overrides.

## Continuous Integration

GitHub Actions automatically validates all models on every push:

1. **Syntax Check** - Validates OpenSCAD syntax
2. **Rendering** - Generates STL files from all `.scad` models
3. **Slicing** - Generates 3MF files with embedded G-code
4. **Validation** - Ensures no slicing errors occurred

Build artifacts (STL, 3MF, logs) are uploaded and available for download from the Actions tab.

## Adding New Projects

1. Create a new directory: `projects/<project-name>/`
2. Add your `.scad` files
3. Add a `README.md` describing the project
4. Commit and push - CI will automatically validate

Files are named `<project-name>__<model-name>.stl` in artifacts to avoid conflicts.
