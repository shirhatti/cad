#!/bin/bash
# Renders OpenSCAD models with GHCR-based caching using ORAS
# Uses content-addressable storage: each .scad file's SHA256 becomes an OCI tag

set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io}"
REPO="${GITHUB_REPOSITORY:-}"
# GHCR package name: use repo name with suffix (ghcr.io/owner/repo-renders)
REPO_NAME="${REPO##*/}"
REPO_OWNER="${REPO%%/*}"
PACKAGE_NAME="${REPO_NAME}-renders"
OPENSCAD_VERSION="${OPENSCAD_VERSION:-$(openscad --version 2>&1 | head -1)}"

# Include OpenSCAD version in cache key to invalidate on upgrades
VERSION_HASH=$(echo "$OPENSCAD_VERSION" | sha256sum | cut -c1-8)

usage() {
    echo "Usage: $0 <scad_file> <output_dir>"
    echo ""
    echo "Environment variables:"
    echo "  GITHUB_REPOSITORY  - Owner/repo for GHCR (required)"
    echo "  REGISTRY           - OCI registry (default: ghcr.io)"
    echo "  SKIP_CACHE         - Set to 1 to skip cache lookup"
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

SCAD_FILE="$1"
OUTPUT_DIR="$2"

if [[ -z "$REPO" ]]; then
    echo "Error: GITHUB_REPOSITORY not set"
    exit 1
fi

if [[ ! -f "$SCAD_FILE" ]]; then
    echo "Error: File not found: $SCAD_FILE"
    exit 1
fi

# Compute content hash of the .scad file
FILE_HASH=$(sha256sum "$SCAD_FILE" | cut -d' ' -f1)
# Combine with OpenSCAD version for full cache key
CACHE_KEY="${VERSION_HASH}-${FILE_HASH}"

# Derive output names
PROJECT_NAME=$(dirname "$SCAD_FILE" | sed 's|^projects/||')
BASENAME=$(basename "$SCAD_FILE" .scad)
FULLNAME="${PROJECT_NAME}__${BASENAME}"

STL_FILE="${OUTPUT_DIR}/stl/${FULLNAME}.stl"
PNG_FILE="${OUTPUT_DIR}/preview/${FULLNAME}.png"

OCI_REF="${REGISTRY}/${REPO_OWNER}/${PACKAGE_NAME}:${CACHE_KEY}"

mkdir -p "${OUTPUT_DIR}/stl" "${OUTPUT_DIR}/preview"

# Try to pull from cache
if [[ "${SKIP_CACHE:-0}" != "1" ]]; then
    echo "Checking cache for ${FULLNAME} (${CACHE_KEY:0:16})..."

    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    if oras pull "$OCI_REF" -o "$TEMP_DIR" 2>/dev/null; then
        echo "✓ Cache hit for ${FULLNAME}"
        cp "${TEMP_DIR}/${FULLNAME}.stl" "$STL_FILE"
        cp "${TEMP_DIR}/${FULLNAME}.png" "$PNG_FILE"
        exit 0
    fi
    echo "✗ Cache miss for ${FULLNAME}, rendering..."
fi

# Render STL
echo "Rendering STL: $SCAD_FILE -> $STL_FILE"
xvfb-run --auto-servernum openscad -o "$STL_FILE" "$SCAD_FILE"

# Render PNG preview
echo "Rendering PNG: $SCAD_FILE -> $PNG_FILE"
xvfb-run --auto-servernum openscad -o "$PNG_FILE" \
    --autocenter --viewall --camera=0,0,0,55,0,25,500 \
    "$SCAD_FILE"

# Push to cache (best effort, don't fail the build)
if [[ "${SKIP_CACHE:-0}" != "1" ]]; then
    echo "Pushing to cache: $OCI_REF"

    PUSH_DIR=$(mktemp -d)
    cp "$STL_FILE" "${PUSH_DIR}/${FULLNAME}.stl"
    cp "$PNG_FILE" "${PUSH_DIR}/${FULLNAME}.png"

    if oras push "$OCI_REF" \
        --artifact-type application/vnd.openscad.render \
        "${PUSH_DIR}/${FULLNAME}.stl:application/sla" \
        "${PUSH_DIR}/${FULLNAME}.png:image/png"; then
        echo "✓ Cached ${FULLNAME}"
    else
        echo "⚠ Failed to cache ${FULLNAME} to ${OCI_REF} (continuing anyway)"
    fi

    rm -rf "$PUSH_DIR"
fi

echo "✓ Rendered ${FULLNAME}"
