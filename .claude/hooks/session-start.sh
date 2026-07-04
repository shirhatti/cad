#!/bin/bash
# SessionStart hook: provision the OpenSCAD toolchain for Claude Code on the web.
#
# The scad-tools CLI (lint/test/check/render/slice) needs OpenSCAD for
# everything except linting. Web sessions start from a fresh container that
# does not ship OpenSCAD, so install it here to match CI (Ubuntu `openscad`
# package, plus xvfb for headless GL). Python deps are handled by `uv sync`.
#
# Idempotent and non-interactive: safe to re-run; skips work already done.
set -euo pipefail

# Only provision the remote (web) container. Local machines manage their own
# toolchain via `just setup` and a system OpenSCAD install.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install OpenSCAD (+ xvfb for headless rendering) if not already present.
if ! command -v openscad >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  # Refresh the package index first: the base image's cached index can be
  # stale enough that pinned .deb versions 404 during install.
  apt-get update
  apt-get install -y --no-install-recommends openscad xvfb
fi

# Sync Python dependencies for the scad-tools CLI (fast no-op when current).
if command -v uv >/dev/null 2>&1; then
  uv sync
fi

openscad --version 2>&1 | head -1 || true
