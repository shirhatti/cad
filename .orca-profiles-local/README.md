# Local Orca Slicer Profile Overrides

This directory contains local overrides for Orca Slicer profiles to fix CLI-specific issues and set better defaults.

The profile paths are constants in `scripts/scad_tools.py` (`ORCA_MACHINE_PROFILE`, `ORCA_PROCESS_PROFILE`, `ORCA_FILAMENT_PROFILE`). The machine and process profiles point here; the filament profile points at the upstream submodule.

## Why Local Overrides?

The upstream OrcaSlicer profiles (from `.orca-slicer` submodule) work in the GUI but need adjustments for CLI usage:

### Machine Profile Override
**Issue**: Bambu Lab printers use relative extruder addressing, which requires `G92 E0` (extruder position reset) in the layer change G-code to prevent floating point accuracy loss.

**Solution**: The GUI automatically adds this when slicing, but the CLI does not. Our machine override adds the required `layer_change_gcode`.

### Process Profile Override
**Issues**:
1. Supports are disabled by default in upstream profiles, requiring manual enabling in GUI.
2. Upstream speeds are conservative compared to Bambu Studio's, giving longer print times than typical GUI usage.
3. Adaptive layer heights for supports gave variable layer heights (0.04-0.28mm) and extra layers on complex geometry.
4. Settings didn't match Bambu Studio defaults (different top layers, infill density, no arc fitting).

**Solutions**: Our process override (`0.20mm Standard @BBL A1.json`) sets:
- `enable_support: 1`, `support_type: normal(auto)`, `support_on_build_plate_only: 0` - automatic supports (also from model overhangs, not just the build plate)
- `outer_wall_speed: 200`, `inner_wall_speed: 300`, `sparse_infill_speed: 270` (mm/s) - matching Bambu Studio
- `tree_support_adaptive_layer_height: 0` and `independent_support_layer_height: 0` - constant 0.2mm layers throughout
- `enable_arc_fitting: 1` - smoother curves
- `top_shell_layers: 5` and `sparse_infill_density: 15%` - matching Bambu Studio quality settings
- `skeleton_infill_line_width` / `skin_infill_line_width: 0.45`

The same file also carries the upstream-derived `default_acceleration` (6000), `travel_speed` (700), and `elefant_foot_compensation` (0.075).

## Structure

```
.orca-profiles-local/
└── BBL/
    ├── machine/
    │   └── Bambu Lab A1 0.4 nozzle.json  # layer_change_gcode fix
    └── process/
        └── 0.20mm Standard @BBL A1.json  # supports, speeds, layer-height fix
```

Filament profiles are loaded directly from the upstream submodule (`.orca-slicer/resources/profiles/BBL/filament/`).

## Tuning history / rationale

Background on why the process overrides look the way they do, from a one-off
comparison of Bambu Studio against the OrcaSlicer CLI (2025-12-26). The numbers
below are historical, from that date's profiles and slicer versions; re-slice
rather than relying on them.

**Layer count / adaptive layer fix.** Before tuning, a complex model (rack
mount) sliced to 137 layers with variable heights (0.04-0.28mm), against 104
constant 0.2mm layers in Bambu Studio. The key fix was
`independent_support_layer_height: 0` (with `tree_support_adaptive_layer_height: 0`);
afterwards the CLI also produced 104 layers at a constant 0.2mm.

**Other overrides.** The speed, arc fitting, top-layer, and infill settings above
were set to match Bambu Studio's defaults so the CLI output is equivalent. A
10mm test cube then matched on layer count (50), layer height, and speeds.

**Time estimates differ.** Even with matching layers and speeds, the CLI's
estimates differed from Bambu Studio's (cube: 341s vs 790s; rack mount: ~8.3h
vs ~3.7h). Likely contributors: acceleration/jerk and pressure-advance
differences, arc fitting, infill algorithm, and each slicer's time-estimation
model. Slicer estimates are unreliable, so compare actual print times, not
estimates, when judging a profile change.

## Updating

When updating the OrcaSlicer submodule:

```bash
cd .orca-slicer
git pull origin main
cd ..
git add .orca-slicer
git commit -m "Update OrcaSlicer profiles"
```

CI does not clone the whole submodule. The "Fetch OrcaSlicer profiles" step in
`.github/workflows/ci.yml` reads the pinned commit from the submodule gitlink
(`git ls-tree HEAD .orca-slicer`) and does a blobless, depth-1, sparse fetch of
only `resources/profiles` at that commit. So the bump must be committed (and the
commit must exist upstream) for CI to pick it up, and anything outside
`resources/profiles` is not available to slicing in CI.

The local overrides will continue to work unless upstream changes the machine or process profile structure significantly.

## Adding Overrides for Other Printers

To add support for other printers that use relative extruder addressing:

1. Copy the machine profile from `.orca-slicer/resources/profiles/[manufacturer]/machine/`
2. Create a minimal JSON with just the override fields:
   ```json
   {
       "type": "machine",
       "name": "Printer Name",
       "inherits": "parent_profile_name",
       "from": "system",
       "layer_change_gcode": "; layer info\nG92 E0 ; reset extruder\n; other commands..."
   }
   ```
3. Point `ORCA_MACHINE_PROFILE` (and `ORCA_PROCESS_PROFILE` / `ORCA_FILAMENT_PROFILE` if needed) in `scripts/scad_tools.py` at the new files

## Background

This issue only affects CLI usage. The GUI works because it dynamically patches profiles at runtime. For CI/reproducible builds, we need these static overrides.
