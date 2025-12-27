#!/bin/bash
# Slices STL models with GHCR-based caching using ORAS
# Cache key includes STL content + slicer profiles + slicer version

set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io}"
REPO="${GITHUB_REPOSITORY:-}"
# GHCR package name: use repo name with suffix (ghcr.io/owner/repo-slices)
REPO_NAME="${REPO##*/}"
REPO_OWNER="${REPO%%/*}"
PACKAGE_NAME="${REPO_NAME}-slices"

usage() {
    echo "Usage: $0 <model_name> <artifacts_dir>"
    echo ""
    echo "  model_name   - Name like 'project__model' (without extension)"
    echo "  artifacts_dir - Directory containing stl/ and where gcode/ will be created"
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

MODEL_NAME="$1"
ARTIFACTS_DIR="$2"

if [[ -z "$REPO" ]]; then
    echo "Error: GITHUB_REPOSITORY not set"
    exit 1
fi

STL_FILE="${ARTIFACTS_DIR}/stl/${MODEL_NAME}.stl"
OUTPUT_FILE="${ARTIFACTS_DIR}/gcode/${MODEL_NAME}.3mf"
LOG_FILE="${ARTIFACTS_DIR}/logs/${MODEL_NAME}.log"

if [[ ! -f "$STL_FILE" ]]; then
    echo "Error: STL file not found: $STL_FILE"
    exit 1
fi

# Compute cache key from:
# 1. STL content hash
# 2. Slicer profiles hash (local overrides)
# 3. Slicer version
STL_HASH=$(sha256sum "$STL_FILE" | cut -d' ' -f1)

# Hash local profile overrides
PROFILES_HASH=""
if [[ -d ".orca-profiles-local" ]]; then
    PROFILES_HASH=$(find .orca-profiles-local -type f -exec sha256sum {} \; 2>/dev/null | sort | sha256sum | cut -c1-16)
else
    PROFILES_HASH="no-local-profiles"
fi

# Get slicer version
SLICER_VERSION=$(orca-slicer --help 2>&1 | head -1 | grep -oP 'v[\d.]+' || echo "unknown")
SLICER_HASH=$(echo "$SLICER_VERSION" | sha256sum | cut -c1-8)

# Cache key: model name + slicer hash + profiles hash + STL hash (truncated for readability)
CACHE_KEY="${MODEL_NAME}-${SLICER_HASH}-${PROFILES_HASH:0:8}-${STL_HASH:0:12}"
OCI_REF="${REGISTRY}/${REPO_OWNER}/${PACKAGE_NAME}:${CACHE_KEY}"

mkdir -p "${ARTIFACTS_DIR}/gcode" "${ARTIFACTS_DIR}/logs"

# Try to pull from cache
if [[ "${SKIP_CACHE:-0}" != "1" ]]; then
    echo "Checking slice cache for ${MODEL_NAME} (${CACHE_KEY:0:20})..."

    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT

    if oras pull "$OCI_REF" -o "$TEMP_DIR" 2>/dev/null; then
        echo "✓ Slice cache hit for ${MODEL_NAME}"
        cp "${TEMP_DIR}/${MODEL_NAME}.3mf" "$OUTPUT_FILE"
        cp "${TEMP_DIR}/${MODEL_NAME}.log" "$LOG_FILE"
        exit 0
    fi
    echo "✗ Slice cache miss for ${MODEL_NAME}, slicing..."
fi

# Run the slicer using just
echo "Slicing: ${MODEL_NAME}"
xvfb-run --auto-servernum just slice "$MODEL_NAME"

# Push to cache (best effort)
if [[ "${SKIP_CACHE:-0}" != "1" ]] && [[ -f "$OUTPUT_FILE" ]]; then
    echo "Pushing slice to cache: $OCI_REF"

    PUSH_DIR=$(mktemp -d)
    cp "$OUTPUT_FILE" "${PUSH_DIR}/${MODEL_NAME}.3mf"
    cp "$LOG_FILE" "${PUSH_DIR}/${MODEL_NAME}.log" 2>/dev/null || touch "${PUSH_DIR}/${MODEL_NAME}.log"

    (
        cd "$PUSH_DIR"
        if oras push "$OCI_REF" \
            --artifact-type application/vnd.orcaslicer.slice \
            "${MODEL_NAME}.3mf:application/vnd.ms-package.3dmanufacturing-3dmodel+xml" \
            "${MODEL_NAME}.log:text/plain"; then
            echo "✓ Cached slice for ${MODEL_NAME}"
        else
            echo "⚠ Failed to cache slice for ${MODEL_NAME} to ${OCI_REF} (continuing anyway)"
        fi
    )

    rm -rf "$PUSH_DIR"
fi

echo "✓ Sliced ${MODEL_NAME}"
