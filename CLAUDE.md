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
just slice        # slice rendered STL to 3MF (needs OpenSCAD + OrcaSlicer)
just render <file>  # render a single file by path
```

Run `uv run scad-tools --help` to use the CLI directly. The linter is pure
Python (tree-sitter) and runs without OpenSCAD installed; rendering, checking,
testing, and slicing require OpenSCAD (and OrcaSlicer for slicing).

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

## CI

`.github/workflows/ci.yml` runs lint → test → check → render → slice on every
push/PR to `main`, and uploads STL/PNG/3MF/log artifacts. Renders and slices
are cached in GHCR via ORAS, keyed by a content hash of each model plus its
dependencies (and the OpenSCAD/OrcaSlicer version).

## Before committing

Run `just lint` at minimum. If OpenSCAD is available, also run `just test` and
`just check`. `pre-commit` runs the linter and unit tests automatically.
