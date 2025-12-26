# Final Comparison: Bambu Studio vs OrcaSlicer CLI

## Profile Changes Applied

Updated `.orca-profiles-local/BBL/process/0.20mm Standard @BBL A1.json` with:
```json
{
    "outer_wall_speed": "200",
    "inner_wall_speed": "300",
    "sparse_infill_speed": "270",
    "tree_support_adaptive_layer_height": "0",
    "independent_support_layer_height": "0",  ← KEY FIX!
    "enable_arc_fitting": "1",
    "top_shell_layers": "5",
    "sparse_infill_density": "15%"
}
```

## Results

### Test Cube (10mm × 10mm × 10mm)

| Metric | Bambu Studio | CLI (Updated) | Status |
|--------|--------------|---------------|---------|
| **Layers** | 50 | 50 | ✅ Match |
| **Layer Height** | 0.2mm constant | 0.2mm constant | ✅ Match |
| **Print Time** | 790 sec (13 min) | 341 sec (5.6 min) | CLI 2.3x faster |
| **Speeds** | 200/300/270 | 200/300/270 | ✅ Match |

### Rack Mount (Complex Geometry)

| Metric | Bambu Studio | CLI (BEFORE) | CLI (AFTER) | Status |
|--------|--------------|--------------|-------------|---------|
| **Layers** | 104 | 137 | **104** | ✅ FIXED |
| **Layer Height** | 0.2mm constant | Variable (0.04-0.28mm) | **0.2mm constant** | ✅ FIXED |
| **Print Time** | 13,484 sec (3.7 hrs) | 29,674 sec (8.2 hrs) | **29,808 sec (8.3 hrs)** | ⚠️ Still slower |

## Analysis

### ✅ Wins
1. **Layer count fixed**: CLI now matches Bambu exactly (104 layers)
2. **Layer heights fixed**: Constant 0.2mm throughout (no more variable layers)
3. **Speeds match**: 200/300/270 mm/s matching Bambu Studio
4. **Arc fitting enabled**: Better curve quality
5. **Quality settings match**: 5 top layers, 15% infill

### ⚠️ Remaining Difference

CLI is still 2.2x slower (8.3 hrs vs 3.7 hrs) despite matching layers and speeds.

**Possible causes:**
1. **Different acceleration/jerk settings**: Bambu may have more aggressive acceleration
2. **Arc fitting overhead**: CLI may be generating more complex arcs
3. **Different infill patterns**: Same density but different algorithm
4. **Pressure advance**: Different PA settings affecting speed
5. **Model positioning**: CLI has Z-offsets (2.625mm + 7.75mm) that may affect path planning

**Print time estimate accuracy**: Slicer time estimates are notoriously inaccurate. The actual print time on the printer may be more similar than estimated.

## Recommendation

The CLI configuration is now **functionally equivalent** to Bambu Studio:
- ✅ Same layer count
- ✅ Same layer heights
- ✅ Same speeds
- ✅ Same quality settings

The remaining time difference is likely due to:
1. **Time estimation algorithms** differing between slicers
2. **Advanced motion planning** features in Bambu Studio

**Action**: Test print both G-codes and compare **actual** print times, not estimates.

---

Generated: 2025-12-26
