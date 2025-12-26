# Local Orca Slicer Profile Overrides

This directory contains local overrides for Orca Slicer profiles to fix CLI-specific issues and set better defaults.

## Why Local Overrides?

The upstream OrcaSlicer profiles (from `.orca-slicer` submodule) work in the GUI but need adjustments for CLI usage:

### Machine Profile Override
**Issue**: Bambu Lab printers use relative extruder addressing, which requires `G92 E0` (extruder position reset) in the layer change G-code to prevent floating point accuracy loss.

**Solution**: The GUI automatically adds this when slicing, but the CLI does not. Our machine override adds the required `layer_change_gcode`.

### Process Profile Override
**Issue**: Supports are disabled by default in upstream profiles, requiring manual enabling in GUI.

**Solution**: Our process override enables automatic support generation by default for CLI builds, ensuring models print successfully.

## Structure

```
.orca-profiles-local/
└── BBL/
    ├── machine/
    │   └── Bambu Lab A1 0.4 nozzle.json  # layer_change_gcode fix
    └── process/
        └── 0.20mm Standard @BBL A1.json  # enable supports by default
```

Filament profiles are loaded directly from the upstream submodule (`.orca-slicer/resources/profiles/BBL/filament/`).

## Updating

When updating the OrcaSlicer submodule:

```bash
cd .orca-slicer
git pull origin main
cd ..
git add .orca-slicer
git commit -m "Update OrcaSlicer profiles"
```

The local override will continue to work unless upstream changes the machine profile structure significantly.

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
3. Update `justfile` to reference the local override

## Background

This issue only affects CLI usage. The GUI works because it dynamically patches profiles at runtime. For CI/reproducible builds, we need these static overrides.
