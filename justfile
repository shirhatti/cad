# Default recipe: list available commands
default:
    @just --list

# ===== SETUP =====

# Bootstrap uv if not installed
_ensure-uv:
    #!/usr/bin/env bash
    if ! command -v uv &> /dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

# Install dependencies and pre-commit hooks
setup: _ensure-uv
    uv sync
    uv run pre-commit install

# Install the pinned headless OpenSCAD + OrcaSlicer from toolchain.toml (Linux x86_64)
toolchain: _ensure-uv
    uv run scad-tools toolchain install

# ===== CORE COMMANDS =====

# Lint all OpenSCAD files
lint: _ensure-uv
    uv run scad-tools lint

# Lint in strict mode (warnings are errors)
lint-strict: _ensure-uv
    uv run scad-tools lint --strict

# Run all OpenSCAD unit tests
test: _ensure-uv
    uv run scad-tools test

# Validate models render without errors
check: _ensure-uv
    uv run scad-tools check

# Render all models to STL + PNG
build: _ensure-uv
    uv run scad-tools render

# Fetch the pinned OrcaSlicer profiles (sparse; no full submodule clone)
profiles: _ensure-uv
    uv run scad-tools profiles fetch

# Check slicer profiles resolve and local overrides are live and spelled right
profiles-lint: _ensure-uv
    uv run scad-tools profiles lint

# Mesh checks on rendered STLs (watertight, bodies, plate fit, walls, overhangs)
mesh: _ensure-uv
    uv run scad-tools mesh

# Slice all STL models to 3MF, verifying slicer settings and print budgets
slice: _ensure-uv
    uv run scad-tools slice

# Render, check, and slice everything, then update print-metrics.json
snapshot: build mesh slice
    uv run scad-tools metrics snapshot

# Show print-metric changes against the committed print-metrics.json
metrics-diff: _ensure-uv
    uv run scad-tools metrics diff print-metrics.json

# Build the static three.js gallery site into _site/ (run `build` first)
gallery: _ensure-uv
    uv run scad-tools gallery

# Render all models then build the gallery site
gallery-build: build gallery

# Serve the built gallery locally at http://localhost:8000
serve-gallery: _ensure-uv
    @echo "Serving _site at http://localhost:8000 (Ctrl+C to stop)"
    uv run python -m http.server 8000 --directory _site

# Run pre-commit hooks
pre-commit: _ensure-uv
    uv run pre-commit run --all-files

# Clean build artifacts
clean:
    rm -rf artifacts/

# ===== SINGLE-FILE COMMANDS =====

# Render a specific file
render file: _ensure-uv
    uv run scad-tools render-file "{{file}}"

# Open file in OpenSCAD GUI
gui file: _ensure-uv
    uv run scad-tools gui "{{file}}"

# Watch and rebuild on changes
watch: _ensure-uv
    watchexec -e scad -- just build

# Watch a specific file
watch-file file: _ensure-uv
    watchexec -w "{{file}}" -- just render "{{file}}"
