# CLAUDE.md

Guidance for working in this repository.

## What this is

Personal CAD projects designed in OpenSCAD and sliced with OrcaSlicer. Each
project lives in its own subdirectory under `projects/`. Models are parametric
and authored to comply with the MakerBot Customizer spec.

## Tooling

All tasks go through the unified `scad-tools` CLI (`scripts/scad_tools.py`),
which is the single source of truth for file discovery, linting, rendering,
and slicing. The `justfile` and CI are thin wrappers around it.

```bash
just setup        # uv sync + install pre-commit hooks
just lint         # MakerBot Customizer linting (tree-sitter based, no OpenSCAD needed)
just lint-strict  # warnings become errors
just test         # run *_test.scad unit tests (needs OpenSCAD)
just check        # validate all models render (needs OpenSCAD)
just build        # render all models to STL + PNG (needs OpenSCAD)
just profiles     # sparse-fetch the pinned OrcaSlicer profiles (.orca-slicer)
just profiles-lint  # broken inheritance, typo'd keys, no-op local overrides
just mesh         # mesh checks + metrics on rendered STLs (no slicer needed)
just slice        # slice rendered STL to 3MF; verify settings + expectations
just snapshot     # build + mesh + slice, then update print-metrics.json
just render <file>  # render a single file by path
just toolchain    # install pinned OpenSCAD + OrcaSlicer (Linux; toolchain.toml)
```

`render`, `check`, `test`, and `slice` process models in parallel (one per CPU
by default; pass `-j N` to limit). Everything is headless: no display or Xvfb.
The pinned OpenSCAD snapshot renders PNG previews offscreen and uses the
Manifold backend (fast, byte-deterministic STLs); OrcaSlicer's CLI slices
without a display. A unit test fails on any OpenSCAD `ERROR:` or
`WARNING:` (e.g. a failed `assert()`), since OpenSCAD itself exits 0 on those.

Run `uv run scad-tools --help` to use the CLI directly. The linter is pure
Python (tree-sitter) and runs without OpenSCAD installed; rendering, checking,
testing, and slicing require OpenSCAD (and OrcaSlicer for slicing).

The CLI itself has a pytest suite in `tests/` (`uv run pytest`); tests that
need a real OpenSCAD are skipped when it isn't on PATH. Changes to `scripts/`
should come with tests.

## File naming conventions

`scad-tools` classifies `.scad` files by filename suffix. These are NOT
rendered or linted as printable models (see `EXCLUDE_SUFFIXES` in
`scad_tools.py`):

- `*_test.scad` — unit tests (run by `just test`)
- `*_lib.scad` — shared library modules (e.g. `retention_bracket_lib.scad`)
- `*_constants.scad` — shared constants (e.g. `shelf_slot_constants.scad`)
- `*_reference.scad` — visualization-only models, not for printing

Everything else is treated as a printable model: it must be Customizer-compliant
(have tabs, descriptions, and parameter annotations) and is rendered + sliced.

Artifact output names are `<project>__<model>` (e.g.
`rack__apple_tv_retention_bracket`).

## Conventions to follow

- Keep shared dimensions in `*_constants.scad` and `include` them in both
  design and test files so alignment math stays in sync. Do not duplicate
  magic numbers across files.
- Design files that can be `include`d by tests guard their top-level render
  with `if (is_undef(RENDER_BRACKET) ? true : RENDER_BRACKET) { ... }` so the
  geometry isn't emitted when a test includes them for its parameters.
- New printable models need Customizer annotations (tabs `/* [Tab] */`, a
  description comment per parameter, and a UI annotation like `// [min:step:max]`).
  Run `just lint` to verify.
- Models too large for the build plate (or otherwise unsliceable) are excluded
  in `pyproject.toml` under `[tool.scad-tools.slice.exclude]` with a reason.
- A model that needs its own slicer settings (e.g. supports off for a
  print-in-place hinge) gets them under
  `[tool.scad-tools.slice.settings."<project>/<model>.scad"]`, with a comment
  saying why. Don't change the shared profiles for one model.
- Every printable model gets expectations in `pyproject.toml` under
  `[tool.scad-tools.expect.models."<project>/<model>.scad"]`: at least
  `max_time` and `max_filament_g` (about 15% above the sliced values), plus
  `bodies` if it isn't one part, and `supports = false` if it's designed
  support-free.
- After changing a model, slicer profile, or the toolchain, run `just snapshot`
  and commit `print-metrics.json`; CI fails when it's stale. Review its diff:
  that's the change in print time, filament, and supports.
- The OrcaSlicer CLI does not resolve profile `inherits`; never pass raw
  profile files to it. `scad-tools slice` flattens them (`scripts/profiles.py`)
  and verifies the 3MF's settings afterwards.

## CI

`.github/workflows/ci.yml` runs pytest → lint (+ profile lint) → test → check →
render → mesh → slice → print-metrics report/check on every branch push and pull request (superseded runs on a ref are auto-cancelled),
and uploads STL/PNG/3MF/log artifacts. Jobs run in a container image
(`ci/Dockerfile`) with the toolchain pinned in `toolchain.toml`; its tag is a
hash of both files, so changing either rebuilds and pushes the image to GHCR
(and mirrors any newly pinned AppImage there). To bump a tool, update its
`version`/`url`/`sha256` in `toolchain.toml`; for OrcaSlicer, also re-pin the
`.orca-slicer` submodule to the matching release tag (see
`.orca-profiles-local/README.md`). Renders and slices
are cached in GHCR via ORAS, keyed by a content hash of each model plus its
dependencies (and the OpenSCAD/OrcaSlicer version). `.github/workflows/prune-cache.yml`
runs `scad-tools cache prune` weekly to delete stale render/slice cache
versions (dry-run by default locally and for manual runs; it never touches the
`ci` image or `toolchain/*` mirror).

## Before committing

Run `just lint` at minimum. If OpenSCAD is available, also run `just test` and
`just check`. After changing `scripts/` or `tests/`, run `uv run pytest`.
`pre-commit` runs the linter, unit tests, and (on Python changes) pytest
automatically, calling `uv run` directly so `just` isn't required.
