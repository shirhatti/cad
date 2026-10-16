# Local Orca Slicer Profile Overrides

This directory holds the few settings where this repo deliberately differs from
the upstream OrcaSlicer profiles (the `.orca-slicer` submodule).

The profile paths are constants in `scripts/profiles.py` (`ORCA_MACHINE_PROFILE`,
`ORCA_PROCESS_PROFILE`, `ORCA_FILAMENT_PROFILE`). The machine and process
profiles point here; the filament profile points at the upstream submodule.

## How profiles reach the slicer

OrcaSlicer's CLI loads each profile file **as-is**: unlike the GUI, it does not
resolve the `inherits` chain. A leaf profile such as `Generic PLA @BBL A1.json`
holds a dozen keys, so passing it directly silently slices with built-in
defaults for everything else. Until this was fixed, every slice ran on a
200×200×100 mm bed at a 200 °C nozzle, with a 2 mm³/s volumetric limit and
0 g/cm³ filament density, which is why the 3MFs reported 0 g of filament and
print times about 3× too long.

So `scad-tools slice` flattens each profile first (`scripts/profiles.py`):

1. Resolve the upstream profile and its whole `inherits` chain.
2. Layer the local override on top. A local file **without** `inherits`
   overrides the upstream profile with the same `type` and `name`. A local file
   **with** `inherits` defines a new profile built on that upstream parent.
3. Write the complete result to `artifacts/profiles/{machine,process,filament}.json`
   and pass those to the CLI: machine and process via `--load-settings`, and
   the filament via `--load-filaments` (a filament passed through
   `--load-settings` is silently ignored).

After slicing, every flattened setting is compared with the settings the slicer
recorded in the 3MF (`Metadata/project_settings.config`). A mismatch fails the
slice, so if the slicer ever stops applying a profile, CI goes red. Three machine
acceleration limits that the 2.3.1 CLI caps at 6000 are allowlisted in
`SLICER_ADJUSTED`, each with a reason.

Useful commands:

```bash
uv run scad-tools profiles show filament   # the exact flattened profile the slicer gets
uv run scad-tools profiles lint            # broken chains, typo'd keys, no-op overrides
```

## The overrides

### Machine (`Bambu Lab A1 0.4 nozzle.json`)
- `layer_change_gcode` adds `G92 E0`. Bambu printers use relative extrusion;
  the GUI adds this reset when slicing, but the CLI does not.

### Process (`0.20mm Standard @BBL A1.json`)
- `enable_support: 1`: auto supports. Upstream defaults to off.
- `tree_support_adaptive_layer_height: 0` and `independent_support_layer_height: 0`:
  constant 0.2 mm layers. Adaptive support layers gave variable 0.04–0.28 mm
  layers and extra layers on complex geometry.
- `skeleton_infill_line_width` / `skin_infill_line_width: 0.45`.

`profiles lint` warns about any override that equals the value it would inherit
anyway. That's how the earlier "match Bambu Studio" speed, arc-fitting,
top-layer, infill, support-type, acceleration and travel overrides were found to
be no-ops and removed: upstream already sets those exact values.

## Structure

```
.orca-profiles-local/
└── BBL/
    ├── machine/
    │   └── Bambu Lab A1 0.4 nozzle.json  # layer_change_gcode fix
    └── process/
        └── 0.20mm Standard @BBL A1.json  # supports, layer-height fix
```

## Tuning history

From a one-off comparison of Bambu Studio and the OrcaSlicer CLI (2025-12-26).
That comparison predates profile flattening, so the CLI side ran mostly on
defaults; it's kept only as the rationale for the support layer-height
overrides. The numbers in `print-metrics.json` are the current ones.

**Layer count / adaptive layer fix.** A complex model (rack mount) sliced to 137
layers with variable heights (0.04–0.28 mm), against 104 constant 0.2 mm layers
in Bambu Studio. `independent_support_layer_height: 0` (with
`tree_support_adaptive_layer_height: 0`) made the CLI produce 104 layers too.

**Time estimates.** The CLI's estimates were then far off Bambu Studio's (10 mm
cube: 341 s vs 790 s; rack mount: about 8.3 h vs 3.7 h), because the CLI was
running on defaults. With flattened profiles the cube estimates 785 s, within
5 s of Bambu Studio. Slicer estimates are still estimates, so compare real print
times when judging a profile change.

## Updating

Keep the submodule pinned to the OrcaSlicer **release tag** matching the
`[tools.orcaslicer]` version in `toolchain.toml` (currently `v2.3.1`), not to
`main`. Profiles from a newer development tree can use keys or values the
pinned slicer binary doesn't understand. Bump both together:

```bash
# 1. Update version/url/sha256 under [tools.orcaslicer] in toolchain.toml
# 2. Re-pin the submodule to the matching tag (no full clone needed)
sha=$(git ls-remote https://github.com/OrcaSlicer/OrcaSlicer.git 'refs/tags/vX.Y.Z' 'refs/tags/vX.Y.Z^{}' | tail -1 | cut -f1)
git update-index --cacheinfo "160000,$sha,.orca-slicer"
git commit -m "Bump OrcaSlicer to X.Y.Z"
# 3. Fetch the new profiles, lint, and re-slice everything
uv run scad-tools profiles fetch
just profiles-lint
just snapshot          # updates print-metrics.json; review and commit the diff
```

If the new slicer adjusts or drops a setting, the post-slice settings check
reports it. Decide whether it's expected (add it to `SLICER_ADJUSTED` with a
reason) or a real problem.

Nobody clones the whole submodule. `uv run scad-tools profiles fetch` (also the
"Fetch OrcaSlicer profiles" step in `.github/workflows/ci.yml`) reads the
pinned commit from the submodule gitlink and does a blobless, depth-1, sparse
fetch of only `resources/profiles` at that commit. So the bump must be committed
(and the commit must exist upstream) to be picked up. The flattened profiles are
the slice cache key, so any change to the effective settings re-slices.

## Adding overrides for other printers

1. Find the upstream profile in `.orca-slicer/resources/profiles/<vendor>/machine/`.
2. Create a minimal JSON with the same `type` and `name` and only the keys you
   want to change (no `inherits`, so it layers on the upstream profile):
   ```json
   {
       "type": "machine",
       "name": "Printer Name",
       "from": "system",
       "layer_change_gcode": "; layer info\nG92 E0 ; reset extruder\n; other commands..."
   }
   ```
3. Point `ORCA_MACHINE_PROFILE` (and `ORCA_PROCESS_PROFILE` /
   `ORCA_FILAMENT_PROFILE` if needed) in `scripts/profiles.py` at the new
   files, and `ORCA_VENDOR` at the vendor directory.
4. Run `just profiles-lint`, then `just snapshot`.
