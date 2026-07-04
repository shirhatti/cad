// HP Elite Mini 800 G9 Vertical Wall Mount
//
// A wall cradle that holds the mini PC flat against the wall in "portrait"
// (vertical) orientation. The lower edge drops into a fully-captured pocket
// (back / front lip / two sides) that carries the weight, while the upper
// edge is held to the wall by two top hooks. The back panel has a large
// ventilation window and keyhole slots for tool-free hanging on wall screws.
//
// Inspired by community "HP Elite Mini 800 G9 vertical mount" designs.
//
// ORIENTATION (in use): the back panel lies flat on the wall; the device's
// large face sits against it and its depth runs vertically. Mount it with the
// rear I/O edge at the OPEN top so ports and cables stay accessible.
//
// PRINT ORIENTATION: as modelled — back panel flat on the bed, walls/hooks
// pointing up (+Z is "out from the wall"). No supports needed; the retaining
// lips are short self-supporting overhangs. Use 3+ perimeters for wall/hook
// strength and print in PETG/ABS for heat tolerance near the PC's exhaust.

/* [Device Dimensions] */
// Device width (HP Elite Mini 800 G9 is 177mm)
device_width = 177; // [120:1:260]
// Device depth — runs vertically up the wall (G9 is 175mm)
device_depth = 175; // [120:1:260]
// Device thickness — protrudes out from the wall (G9 is 34mm)
device_thickness = 34; // [20:1:80]

/* [Fit] */
// Clearance added around the device on each side
clearance = 1; // [0.25:0.25:3]

/* [Cradle] */
// Perimeter wall / rail thickness
wall_thickness = 4; // [2:0.5:8]
// Back panel thickness (sits against the wall)
back_thickness = 4; // [2:0.5:8]
// Height of the bottom capture pocket that fully grips the lower edge
pocket_height = 45; // [25:1:90]
// How far retaining lips reach inward over the device's outer face
lip_reach = 6; // [3:0.5:12]
// Lip thickness (measured out from the wall)
lip_thickness = 3; // [2:0.5:6]

/* [Ventilation] */
// Border width of solid back panel around the vent window
vent_margin = 22; // [10:1:40]
// Corner radius of the back-panel vent window
vent_radius = 12; // [0:1:30]
// Number of airflow slots per side rail
rail_slots = 3; // [0:1:6]

/* [Wall Mounting] */
// Screw shank diameter for keyhole slots and bottom screws
screw_shank = 4.5; // [3:0.5:6]
// Screw head diameter (keyhole entry / countersink)
screw_head = 9; // [6:0.5:14]
// Vertical travel of the keyhole slot (hang-and-drop distance)
keyhole_travel = 10; // [6:1:20]

/* [Rendering] */
$fa = 2;
$fn = 48;

/* [Hidden] */
eps = 0.01;

// ---- Derived layout (print orientation: X width, Y up-the-wall, Z out) ----
plate_w = device_width + 2 * clearance + 2 * wall_thickness;   // X
plate_h = wall_thickness + device_depth + clearance + wall_thickness; // Y
cavity_z = back_thickness + device_thickness + clearance;      // top of device
lip_top_z = cavity_z + lip_thickness;

// Device footprint on the panel
dev_x0 = wall_thickness + clearance;
dev_x1 = plate_w - wall_thickness - clearance;
dev_y0 = wall_thickness + clearance;           // rests on the bottom shelf
dev_y1 = dev_y0 + device_depth;

// ============================================================
// Helpers
// ============================================================

// 2D rounded rectangle anchored at origin (corner), rounded corners.
module rrect(w, h, r) {
    rr = min(r, w / 2, h / 2);
    if (rr <= 0) {
        square([w, h]);
    } else {
        hull() {
            for (x = [rr, w - rr], y = [rr, h - rr])
                translate([x, y]) circle(r = rr);
        }
    }
}

// A keyhole cut: large entry circle at the bottom, narrow slot rising +Y.
// Cut through the panel in Z. Positioned by its entry-circle centre.
module keyhole_cut(shank_d, head_d, travel) {
    translate([0, 0, -eps])
    linear_extrude(height = back_thickness + 2 * eps) {
        circle(d = head_d);
        translate([-shank_d / 2, 0]) square([shank_d, travel]);
        translate([0, travel]) circle(d = shank_d);
    }
}

// Countersunk through-hole for a bottom fixing screw. The countersink opens
// toward the interior (+Z) so the flat head sits flush under the device.
module screw_cut(shank_d, head_d) {
    csk = (head_d - shank_d) / 2;
    translate([0, 0, -eps])
        cylinder(h = back_thickness + 2 * eps, d = shank_d);
    translate([0, 0, back_thickness - csk])
        cylinder(h = csk + eps, d1 = shank_d, d2 = head_d);
}

// ============================================================
// Components
// ============================================================

// Solid overlap used everywhere walls/lips meet, so unions stay 2-manifold
// (no measure-zero coincident faces) instead of merely touching.
grab = 1.5;

// Back panel with a rounded ventilation window and wall fixings.
module back_panel() {
    win_w = device_width - 2 * (vent_margin - clearance);
    win_h = device_depth - 2 * (vent_margin - clearance);

    difference() {
        linear_extrude(height = back_thickness)
            rrect(plate_w, plate_h, 4);

        // Ventilation window behind the device.
        if (win_w > 0 && win_h > 0)
            translate([plate_w / 2 - win_w / 2, dev_y0 + (device_depth - win_h) / 2, -eps])
                linear_extrude(height = back_thickness + 2 * eps)
                    rrect(win_w, win_h, vent_radius);

        // Two keyhole slots high on the panel, above the vent window.
        kh_y = dev_y1 - vent_margin / 2;
        for (kx = [plate_w * 0.30, plate_w * 0.70])
            translate([kx, kh_y, 0]) keyhole_cut(screw_shank, screw_head, keyhole_travel);

        // Two countersunk screw holes low on the panel, inside the pocket zone.
        for (sx = [plate_w * 0.30, plate_w * 0.70])
            translate([sx, vent_margin / 2, 0]) screw_cut(screw_shank, screw_head);
    }
}

// One perimeter wall rising to the device's outer face, with airflow slots.
//   ax0..ax1, ay0..ay1 = wall footprint in X/Y; slots run along the long axis.
module perimeter_wall(ax0, ay0, ax1, ay1, slots) {
    w = ax1 - ax0;
    d = ay1 - ay0;
    along_y = d >= w;
    length = along_y ? d : w;

    difference() {
        translate([ax0, ay0, 0]) cube([w, d, cavity_z]);

        if (slots > 0) {
            span = length * 0.7;
            step = span / slots;
            sw = step * 0.5;
            for (i = [0 : slots - 1]) {
                pos = (along_y ? ay0 : ax0) + length * 0.15 + step * (i + 0.5);
                if (along_y)
                    translate([ax0 - eps, pos - sw / 2, cavity_z * 0.30])
                        cube([w + 2 * eps, sw, cavity_z * 0.45]);
                else
                    translate([pos - sw / 2, ay0 - eps, cavity_z * 0.30])
                        cube([sw, d + 2 * eps, cavity_z * 0.45]);
            }
        }
    }
}

// A retaining lip capping a wall top and reaching inward over the device face.
// The lip bites `grab` back into the wall it sits on (a solid weld) and reaches
// `lip_reach` past the wall's inner face over the device.
//   edge: "bottom" reaches +Y, "left" reaches +X, "right" reaches -X
//   x0,y0,x1,y1: the footprint of the wall being capped.
module lip(edge, x0, y0, x1, y1) {
    z0 = cavity_z - grab;                 // bite down into the wall for a solid weld
    h  = grab + lip_thickness;
    if (edge == "bottom")            // shelf wall at Y[y1,y0]; reach inward from y0
        translate([x0, y0 - grab, z0]) cube([x1 - x0, lip_reach + grab, h]);
    else if (edge == "left")         // wall at X[x0,x1]; reach inward from inner face x1
        translate([x1 - grab, y0, z0]) cube([lip_reach + grab, y1 - y0, h]);
    else if (edge == "right")        // wall at X[x0,x1]; reach inward from inner face x0
        translate([x0 - lip_reach, y0, z0]) cube([lip_reach + grab, y1 - y0, h]);
}

// The U of perimeter walls (bottom shelf + two full-height sides).
module walls() {
    // Bottom shelf (carries the device weight in use), full width.
    perimeter_wall(0, 0, plate_w, wall_thickness, 0);
    // Left and right side walls, full height, with airflow slots.
    perimeter_wall(0, wall_thickness - grab, wall_thickness, plate_h, rail_slots);
    perimeter_wall(plate_w - wall_thickness, wall_thickness - grab, plate_w, plate_h, rail_slots);
}

// Retaining lips: full-width bottom lip + short lower-side lips trap the lower
// edge on all sides; two top hooks hold the upper edge to the wall.
module lips() {
    inner_x0 = wall_thickness;
    inner_x1 = plate_w - wall_thickness;

    // Bottom lip over the lower edge.
    lip("bottom", inner_x0, wall_thickness, inner_x1, 0);

    // Lower side lips (within the capture pocket).
    lip("left",  0, wall_thickness, wall_thickness, pocket_height);
    lip("right", plate_w - wall_thickness, wall_thickness, plate_w, pocket_height);

    // Top hooks: inward lips on the top of each side wall.
    hook = 28;  // length of the top hook zone
    lip("left",  0, plate_h - hook, wall_thickness, plate_h);
    lip("right", plate_w - wall_thickness, plate_h - hook, plate_w, plate_h);
}

// ============================================================
// Assembly
// ============================================================
module wall_mount() {
    back_panel();
    walls();
    lips();
}

// Guard: skip rendering when included by another file (e.g. tests).
if (is_undef(RENDER_MOUNT) ? true : RENDER_MOUNT) {
    wall_mount();
}
