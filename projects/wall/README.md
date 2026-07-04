# Wall Mounts

3D-printable wall-mounting cradles for small devices, designed to hang flat
against a wall with tool-free keyhole mounting.

## Projects

### HP Elite Mini 800 G9 Vertical Wall Mount (`elitemini_800_g9_wall_mount.scad`)

A vertical wall cradle that holds the HP Elite Mini 800 G9 flat against the
wall in "portrait" orientation. The lower edge drops into a capture pocket
that is closed on all four sides (back panel, front lip, and two side lips) and
carries the PC's weight, while two top hooks hold the upper edge to the wall.
The back panel has a large ventilation window and hangs on the wall via keyhole
slots, so no fasteners are visible from the front.

**Features:**
- Fully-captured bottom pocket (weight-bearing) + two top retaining hooks
- Large back-panel ventilation window plus airflow slots in both side walls
- Two keyhole slots for tool-free hanging on pre-installed wall screws
- Two countersunk holes for optional bottom fixing screws (heads sit flush
  under the device)
- Prints flat with no supports; retaining lips are short self-supporting
  overhangs
- Fully parametric via Customizer (fits other mini PCs by changing the three
  device dimensions)

**Device Specs (HP Elite Mini 800 G9):**
- Dimensions: 177mm (W) × 175mm (D) × 34mm (H/thickness)
- Weight: ~1.4kg (3.13 lb)
- Reference design: [HP Elite Mini 800 G9 PC Vertical Mount](https://www.printables.com/model/1221816-hp-elite-mini-800-g9-pc-vertical-mount/files)

**Printed part:**
- Footprint: 187mm × 184mm × 42mm (fits a 256 × 256mm build plate)

**Orientation (in use):**
- Back panel flat against the wall; the PC's large face rests on it and its
  175mm depth runs vertically.
- Mount with the **rear I/O edge at the open top** so ports and cables stay
  accessible; cables drape down behind or over the top.

**Assembly:**
1. Print the cradle (back panel on the bed, walls/hooks up — no supports).
2. Drive two wall screws at the keyhole spacing (`~75mm` apart at this device
   width; measure the printed slots), leaving the heads slightly proud.
3. Hang the cradle on the screws and slide it down so the shanks seat in the
   narrow part of the keyholes.
4. (Optional) Add two screws through the lower countersunk holes for extra
   security.
5. Tilt the PC so its top edge slips under the top hooks, then lower the bottom
   edge into the capture pocket until the lips engage.

**Hardware Required:**
- 2× wall screws/anchors sized for `screw_shank` / `screw_head` (defaults suit
  a #8 / M4 screw)
- 2× optional M4 screws for the bottom fixing holes

**Print Settings:**
- Material: PETG or ABS recommended (heat tolerance near the PC exhaust)
- Layer Height: 0.20mm
- Infill: 20-30%
- Perimeters: 3+ for wall and hook strength
- Supports: None required

## Customizing for another device

Change `device_width`, `device_depth`, and `device_thickness` in the
Customizer. All wall, pocket, lip, ventilation, and mounting geometry is
derived from those three values plus the fit/cradle parameters. Run
`just lint` and `just test` to confirm the geometry stays consistent.
