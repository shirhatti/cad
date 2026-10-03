#!/bin/bash
# SessionStart hook: provision the OpenSCAD toolchain for Claude Code on the web.
#
# The scad-tools CLI (lint/test/check/render/slice) needs OpenSCAD for
# everything except linting. Web sessions start from a fresh container, so
# install the same pinned OpenSCAD build CI uses (toolchain.toml) via
# `scad-tools toolchain install`. It renders headless: no display or Xvfb.
# OrcaSlicer is skipped here (its GTK/WebKit runtime is large); install it with
# `uv run scad-tools toolchain install orcaslicer` if a session needs to slice.
#
# Idempotent and non-interactive: safe to re-run; skips work already done.
set -euo pipefail

# Only provision the remote (web) container. Local machines manage their own
# toolchain via `just setup`.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

# GL/X runtime libs the OpenSCAD AppImage expects from the host (see
# ci/Dockerfile). Only touch apt if one is missing.
if ! ldconfig -p | grep -q 'libOpenGL.so.0' || ! ldconfig -p | grep -q 'libSM.so.6'; then
  export DEBIAN_FRONTEND=noninteractive
  # Refresh the index first: the base image's cached one can be stale enough
  # that pinned .deb versions 404 during install.
  apt-get update
  apt-get install -y --no-install-recommends libegl1 libgl1 libopengl0 libsm6 libice6
fi

# Sync Python deps, then install the pinned OpenSCAD into ~/.local/bin (a
# fast no-op when already current).
uv sync
uv run scad-tools toolchain install openscad

openscad --version 2>&1 | head -1 || true
