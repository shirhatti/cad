# Desk Mounts

3D-printable mounts for stashing desk accessories under a desk, on a wall, or
inside a cabinet.

## Projects

### Lenovo 135W AC Adapter Clamp (`lenovo_135w_adapter_clamp.scad`)

A screw-down saddle clamp for the Lenovo 135W slim-tip power brick
(model ADL135NLC3A, FRU 45N0554, PN 45N0365 / PA-1131-72). Each clamp is a
U-shaped strap that wraps over the brick, with a flange on each side carrying
a countersunk screw hole. Use two clamps per brick, one near each end — the
narrow straps leave both cables free.

The strap's inner height is `squeeze` (0.5mm) less than the brick's thickness,
so tightening the screws flexes the strap and holds the brick firmly.

**Features:**
- Rounded inner corners that follow the brick's edges
- Countersunk screw holes — heads sit flush in the flanges
- Prints flat with the strap profile on the bed: strong bends, no supports
- Prints `clamp_count` (default 2) clamps in one plate
- Fully parametric via Customizer (fits other bricks by changing the width and
  thickness)

**Default dimensions:**
- Brick: 72mm wide × 25mm thick (nominal — **measure yours with calipers**
  and set `adapter_width` / `adapter_thickness` before printing)
- Each clamp: 107mm span × 27.5mm tall × 20mm wide
- Screw centres: 93mm apart

**Hardware Required:**
- 4× #8 or M4 countersunk wood screws, ~16mm long for a desk underside
  (adjust `screw_hole` / `screw_head` for other screws)

**Installation:**
1. Hold the brick in place and slip a clamp over each end.
2. Mark and pilot-drill the screw holes.
3. Screw the clamps down until the flanges are flush with the surface.

**Print Settings:**
- Material: PETG recommended (the brick runs warm)
- Layer Height: 0.20mm
- Infill: 30%+
- Perimeters: 3+
- Supports: None required
