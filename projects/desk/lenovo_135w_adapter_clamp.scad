// Lenovo 135W AC Adapter Clamp Mount (ADL135NLC3A / 45N0365 / PA-1131-72)
//
// A screw-down saddle clamp that holds the power brick flat against a
// surface — under a desk, on a wall, or inside a cabinet. Each clamp is a
// U-shaped strap that wraps over the brick, with a flange on each side
// carrying a countersunk screw hole. Use two clamps per brick, one near each
// end; the straps are narrow so both cables exit freely.
//
// The strap's inner height is slightly LESS than the brick's thickness
// (`squeeze`), so driving the screws flexes the strap and clamps the brick
// tight instead of letting it rattle.
//
// DATUM: origin at the mounting surface, centred on the brick's width.
//   X = across the brick width, Y = out from the mounting surface,
//   Z = along the brick length (the strap width).
//
// PRINT ORIENTATION: as modelled — the strap profile lies flat on the bed and
// is extruded upward by `strap_width`. Layer lines follow the U so the bends
// are strong; no supports needed (the screw holes are small horizontal bores).
// PETG recommended: the brick runs warm.

/* [Adapter Dimensions] */
// Adapter width — across the brick (measure yours with calipers)
adapter_width = 72; // [40:0.5:120]
// Adapter thickness — how far it stands off the mounting surface
adapter_thickness = 25; // [15:0.5:50]
// Radius of the adapter's rounded long edges
adapter_edge_radius = 4; // [0:0.5:10]

/* [Fit] */
// Side clearance between the strap and the brick, per side
clearance = 0.5; // [0:0.25:2]
// Interference on thickness so tightening the screws clamps the brick
squeeze = 0.5; // [0:0.25:2]

/* [Strap] */
// Strap width (along the brick's length)
strap_width = 20; // [10:1:40]
// Strap wall thickness
strap_thickness = 3; // [2:0.5:6]
// Number of clamps to lay out on the build plate
clamp_count = 2; // [1:1:4]
// Gap between clamps on the build plate
plate_gap = 6; // [2:1:20]

/* [Mounting Flanges] */
// How far each flange extends beyond the strap wall
flange_length = 14; // [8:1:30]
// Flange thickness (screw clamping length)
flange_thickness = 5; // [3:0.5:10]
// Screw shank hole diameter (4.5 suits #8 / M4 wood screws)
screw_hole = 4.5; // [2.5:0.5:6]
// Screw head diameter for the countersink (0 for a plain hole)
screw_head = 8.5; // [0:0.5:14]

/* [Rendering] */
$fa = 2;
$fn = 48;

/* [Hidden] */
eps = 0.01;

// ---- Derived profile dimensions ----
inner_w = adapter_width + 2 * clearance;      // cavity width
inner_h = adapter_thickness - squeeze;        // cavity height off the surface
inner_r = min(adapter_edge_radius + clearance, inner_w / 2, inner_h);
outer_w = inner_w + 2 * strap_thickness;
outer_h = inner_h + strap_thickness;
outer_r = inner_r + strap_thickness;
total_w = outer_w + 2 * flange_length;        // overall clamp span in X
csk_depth = screw_head > screw_hole ? (screw_head - screw_hole) / 2 : 0;
// Screw hole centre, measured outward from the strap's outer wall.
screw_offset = flange_length / 2;
screw_x = outer_w / 2 + screw_offset;

echo(str("Clamp span ", total_w, "mm, height ", outer_h, "mm, width ", strap_width, "mm"));
echo(str("Screw centres ", 2 * screw_x, "mm apart"));
assert(squeeze < adapter_thickness / 4, "squeeze is unreasonably large");
assert(screw_head == 0 || screw_head > screw_hole, "screw head must exceed the shank");
assert(csk_depth < flange_thickness - 1, "countersink leaves no flange material");
assert(screw_head < flange_length, "screw head would hit the strap wall");

// ============================================================
// Helpers
// ============================================================

// 2D "tombstone": a rectangle from y = 0 up to h, centred on x = 0, with
// its two TOP corners rounded to r.
module top_rounded_rect(w, h, r) {
    rr = max(min(r, w / 2, h), eps);
    hull() {
        for (x = [-w / 2 + rr, w / 2 - rr])
            translate([x, h - rr]) circle(r = rr);
        translate([-w / 2, 0]) square([w, h - rr]);
    }
}

// ============================================================
// Components
// ============================================================

// The clamp cross-section (XY): U-strap + two flanges, open at the surface.
module clamp_profile() {
    difference() {
        union() {
            top_rounded_rect(outer_w, outer_h, outer_r);
            translate([-total_w / 2, 0]) square([total_w, flange_thickness]);
        }
        translate([0, -eps]) top_rounded_rect(inner_w, inner_h + eps, inner_r);
    }
}

// Countersunk screw bore through a flange, running along Y. The countersink
// opens away from the mounting surface so the head sits flush.
module screw_cut() {
    rotate([-90, 0, 0]) {
        translate([0, 0, -eps])
            cylinder(h = flange_thickness + 2 * eps, d = screw_hole);
        if (csk_depth > 0)
            translate([0, 0, flange_thickness - csk_depth])
                cylinder(h = csk_depth + eps, d1 = screw_hole, d2 = screw_head);
    }
}

module clamp() {
    difference() {
        linear_extrude(height = strap_width) clamp_profile();
        for (sx = [-screw_x, screw_x])
            translate([sx, 0, strap_width / 2]) screw_cut();
    }
}

// ============================================================
// Assembly — clamps laid out side by side for printing
// ============================================================
module clamp_set() {
    pitch = outer_h + plate_gap;
    for (i = [0 : clamp_count - 1])
        translate([0, i * pitch, 0]) clamp();
}

// Guard: skip rendering when included by another file (e.g. tests).
if (is_undef(RENDER_CLAMP) ? true : RENDER_CLAMP) {
    clamp_set();
}
