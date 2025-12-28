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

# Slice all STL models to 3MF
slice: _ensure-uv
    uv run scad-tools slice

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
