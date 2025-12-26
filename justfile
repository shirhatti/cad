# Default recipe: list available commands
default:
    @just --list

# ===== SETUP & DEPENDENCIES =====

# Bootstrap uv (Python package manager)
_ensure-uv:
    #!/usr/bin/env bash
    if ! command -v uv &> /dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi

# Install Python dependencies and pre-commit hooks
setup: _ensure-uv
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Syncing Python dependencies..."
    uv sync
    echo "Installing pre-commit hooks..."
    uv run pre-commit install
    echo "✓ Setup complete!"

# ===== LINTING =====

# Run Customizer linter on all OpenSCAD files
lint: _ensure-uv
    uv run python -m scripts.customizer_lint projects/

# Run Customizer linter in strict mode (warnings are errors)
lint-strict: _ensure-uv
    uv run python -m scripts.customizer_lint --strict projects/

# Run all pre-commit hooks on all files
pre-commit: _ensure-uv
    uv run pre-commit run --all-files

# ===== OPENSCAD =====

# Find OpenSCAD binary (Homebrew install)
_openscad_app := `brew info --cask openscad --json=v2 2>/dev/null | jq -r '.casks[0].artifacts[] | select(.app?) | .app[0]'`
_openscad := "/Applications" / _openscad_app
_openscad_bin := _openscad / "Contents/MacOS/OpenSCAD"

# Orca Slicer binary path
# Install from: https://github.com/OrcaSlicer/OrcaSlicer/releases
_orca_slicer_bin := "/Applications/OrcaSlicer.app/Contents/MacOS/OrcaSlicer"

# Orca Slicer profile configuration
# Profiles from upstream submodule, with local overrides for CLI compatibility
_orca_profiles_upstream := ".orca-slicer/resources/profiles/BBL"
_orca_profiles_local := ".orca-profiles-local/BBL"
_orca_machine_profile := _orca_profiles_local / "machine/Bambu Lab A1 0.4 nozzle.json"
_orca_process_profile := _orca_profiles_local / "process/0.20mm Standard @BBL A1.json"
_orca_filament_profile := _orca_profiles_upstream / "filament/Generic PLA @BBL A1.json"

# Helper function to run OpenSCAD quietly (suppress OpenGL warnings)
_run_openscad := "\"" + _openscad_bin + "\" \"$@\" 2>/dev/null"

# Build all .scad files to .stl (searches projects subdirectories)
build:
    #!/usr/bin/env bash
    set -euo pipefail
    openscad() { {{_openscad_bin}} "$@" 2>/dev/null; }
    mkdir -p artifacts/stl

    # Find all .scad files in projects/
    find projects -name "*.scad" -type f | while read -r f; do
        project_name=$(dirname "$f" | sed 's|projects/||')
        basename=$(basename "$f" .scad)
        out="artifacts/stl/${project_name}__${basename}.stl"
        echo "Rendering $f -> $out"
        openscad -o "$out" "$f"
    done
    echo "Done. STL files in ./artifacts/stl/"

# Render a specific file to STL
render file:
    #!/usr/bin/env bash
    mkdir -p artifacts/stl
    # Strip .scad extension if provided
    basename="{{file}}"
    basename="${basename%.scad}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    echo "Rendering ${basename}.scad..."
    {{_openscad_bin}} -o "artifacts/stl/${basename}_${timestamp}.stl" "${basename}.scad"
    # Also create a symlink without timestamp for easy reference
    ln -sf "${basename}_${timestamp}.stl" "artifacts/stl/${basename}.stl"
    echo "✓ Rendered to: artifacts/stl/${basename}.stl"

# Watch for changes and auto-rebuild all files
watch:
    @echo "Watching for .scad changes... (Ctrl+C to stop)"
    watchexec -e scad -c -- just build

# Watch and rebuild a specific file
watch-file file:
    #!/usr/bin/env bash
    basename="{{file}}"
    basename="${basename%.scad}"
    echo "Watching ${basename}.scad... (Ctrl+C to stop)"
    watchexec -w "${basename}.scad" -c -- just render "${basename}"

# Generate PNG preview for a file
preview file:
    #!/usr/bin/env bash
    openscad() { {{_openscad_bin}} "$@" 2>/dev/null; }
    mkdir -p artifacts/preview
    # Strip .scad extension if provided
    basename="{{file}}"
    basename="${basename%.scad}"
    openscad -o "artifacts/preview/${basename}.png" --autocenter --viewall --camera=0,0,0,55,0,25,500 "${basename}.scad"

# Generate PNG previews for all files
preview-all:
    #!/usr/bin/env bash
    set -euo pipefail
    openscad() { {{_openscad_bin}} "$@" 2>/dev/null; }
    mkdir -p artifacts/preview
    for f in *.scad; do
        [ -f "$f" ] || continue
        out="artifacts/preview/${f%.scad}.png"
        echo "Rendering preview: $f -> $out"
        openscad -o "$out" --autocenter --viewall --camera=0,0,0,55,0,25,500 "$f"
    done
    echo "Done. PNG previews in ./artifacts/preview/"

# Open a file in OpenSCAD GUI
gui file:
    #!/usr/bin/env bash
    basename="{{file}}"
    basename="${basename%.scad}"
    "{{_openscad_bin}}" "${basename}.scad" >/dev/null 2>&1 &

# Clean build artifacts
clean:
    rm -rf artifacts/

# Validate models render without errors (catches manifold/geometry issues)
check:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    find projects -name "*.scad" -type f | while read -r f; do
        echo "Rendering $f..."
        if ! {{_openscad_bin}} -o /dev/null "$f" 2>/dev/null; then
            echo "  ✗ FAILED"
            failed=1
        else
            echo "  ✓ OK"
        fi
    done
    exit $failed

# Export high-quality render (slower, better quality)
render-hq file:
    #!/usr/bin/env bash
    openscad() { {{_openscad_bin}} "$@" 2>/dev/null; }
    mkdir -p artifacts/stl
    # Strip .scad extension if provided
    basename="{{file}}"
    basename="${basename%.scad}"
    timestamp=$(date +%Y%m%d_%H%M%S)
    openscad -o "artifacts/stl/${basename}_${timestamp}.stl" --render "${basename}.scad"
    # Also create a symlink without timestamp for easy reference
    ln -sf "${basename}_${timestamp}.stl" "artifacts/stl/${basename}.stl"

# Helper to run commands with xvfb if needed (headless environment)
_xvfb_run := if env("DISPLAY", "") == "" { "xvfb-run -a" } else { "" }

# Slice an STL file to 3MF using Orca Slicer (Bambu A1)
slice file:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p artifacts/gcode artifacts/logs
    # Strip .scad extension if provided
    basename="{{file}}"
    basename="${basename%.scad}"
    input="artifacts/stl/${basename}.stl"
    timestamp=$(date +%Y%m%d_%H%M%S)
    output="artifacts/gcode/${basename}_${timestamp}.3mf"

    if [ ! -f "$input" ]; then
        echo "Error: $input not found. Run 'just render ${basename}' first."
        exit 1
    fi

    echo "Slicing $input with profiles:"
    echo "  Machine: {{_orca_machine_profile}}"
    echo "  Process: {{_orca_process_profile}}"
    echo "  Filament: {{_orca_filament_profile}}"

    # Build settings argument: machine;process;filament
    settings="{{_orca_machine_profile}};{{_orca_process_profile}};{{_orca_filament_profile}}"

    # Make paths absolute for Orca Slicer
    abs_input="$(pwd)/$input"
    abs_output="$(pwd)/$output"

    # Use xvfb-run in headless environments for thumbnail generation
    {{_xvfb_run}} {{_orca_slicer_bin}} \
        --load-settings "$settings" \
        --slice 0 \
        --export-3mf "$abs_output" \
        "$abs_input" \
        2>&1 | tee "artifacts/logs/${basename}_${timestamp}_slice.log"

    if [ -f "$output" ]; then
        # Create a symlink without timestamp for easy reference
        ln -sf "${basename}_${timestamp}.3mf" "artifacts/gcode/${basename}.3mf"
        echo "✓ Sliced 3MF saved to: $output"
        echo "  (Symlinked as: artifacts/gcode/${basename}.3mf)"
        echo "  (Contains G-code - can be sent to printer or opened in Orca Slicer)"
    else
        echo "✗ Slicing failed - check artifacts/logs/${basename}_${timestamp}_slice.log for details"
        cat "artifacts/logs/${basename}_${timestamp}_slice.log"
        exit 1
    fi

# Slice all models in artifacts/stl
slice-all:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -d "artifacts/stl" ]; then
        echo "Error: artifacts/stl not found. Run 'just build' first."
        exit 1
    fi
    for stl in artifacts/stl/*.stl; do
        [ -f "$stl" ] || continue
        # Skip symlinks (we only want timestamped files)
        [ -L "$stl" ] && continue
        basename=$(basename "$stl" .stl)
        echo "Slicing $basename..."
        just slice "$basename"
    done
    echo "✓ All models sliced. 3MF files in artifacts/gcode/"

# Open sliced 3MF in Orca Slicer for review and manual printing
open-slice file:
    #!/usr/bin/env bash
    # Strip .scad extension if provided
    basename="{{file}}"
    basename="${basename%.scad}"
    if [ ! -f "artifacts/gcode/${basename}.3mf" ]; then
        echo "Error: artifacts/gcode/${basename}.3mf not found. Run 'just slice ${basename}' first."
        exit 1
    fi
    echo "Opening artifacts/gcode/${basename}.3mf in Orca Slicer..."
    open -a OrcaSlicer "artifacts/gcode/${basename}.3mf"

# Complete workflow: render, slice, and open for review
prepare file:
    #!/usr/bin/env bash
    basename="{{file}}"
    basename="${basename%.scad}"
    just render "${basename}"
    just slice "${basename}"
    just open-slice "${basename}"
