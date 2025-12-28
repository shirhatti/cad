// Apple TV Retention Bracket for 1U Vented Rack Shelf
//
// A top-down retention bracket that secures an Apple TV 4K to a vented rack shelf.
// Uses shared retention_bracket_lib for common bracket geometry.
//
// PRINT ORIENTATION: Print upside-down (top plate on build plate, bosses up).
// No supports needed. Use 3+ perimeters for insert boss strength.

include <retention_bracket_lib.scad>

/* [Device Dimensions] */
// Device size (Apple TV 4K 2nd gen is 98mm square)
device_size = 98; // [80:1:120]
// Device height
device_height = 35; // [20:1:50]

/* [Bracket Dimensions] */
// Clearance around device (total, split between sides)
clearance = 0.5; // [0.5:0.5:5]
// Side wall thickness
wall_thickness = 10; // [5:1:15]
// Top plate thickness
top_plate_thickness = 3; // [2:0.5:5]

/* [Retention Lip] */
// How far the lip extends inward over the device
lip_overhang = 4; // [2:1:10]
// Thickness of the lip (vertical, hangs down from top plate)
lip_thickness = 6; // [2:1:10]
// Corner radius for squircle shape
corner_radius = 10; // [5:1:20]

/* [Threaded Insert Bosses] */
// Insert size: M4 or M5
insert_size = "M4"; // [M4, M5]
// Boss outer diameter
boss_diameter = 12; // [10:1:20]
// Boss height
boss_height = 10; // [8:1:15]
// M4 insert hole diameter
m4_hole_diameter = 5.6; // [5.0:0.1:6.0]
// M5 insert hole diameter
m5_hole_diameter = 6.4; // [6.0:0.1:7.0]
// Insert hole depth
insert_hole_depth = 8; // [6:1:12]
// Front boss distance from front edge
front_boss_offset = 15; // [10:1:30]
// Back boss distance from back edge
back_boss_offset = 15; // [10:1:30]
// Boss overhang from wall (for slot alignment)
boss_overhang = 6.75; // [0:0.25:20]

/* [Rendering] */
$fa = 1;
$fn = 64;

// ============================================================
// Derived dimensions (exported for tests)
// ============================================================

insert_hole_diameter = (insert_size == "M5") ? m5_hole_diameter : m4_hole_diameter;
bracket_width = calc_bracket_width(device_size, clearance, lip_overhang, wall_thickness);
bracket_depth = calc_bracket_depth(device_size, clearance, lip_overhang);
boss_span = calc_boss_span(device_size, clearance, lip_overhang, wall_thickness, boss_overhang);

// ============================================================
// Main model (print orientation: top plate on bed, bosses up)
// ============================================================

// Guard: skip rendering if included by another file (e.g., tests)
if (is_undef(RENDER_BRACKET) ? true : RENDER_BRACKET) {
    retention_bracket_printable(
        device_size = device_size,
        device_height = device_height,
        clearance = clearance,
        wall_thickness = wall_thickness,
        top_plate_thickness = top_plate_thickness,
        lip_overhang = lip_overhang,
        lip_thickness = lip_thickness,
        corner_radius = corner_radius,
        boss_diameter = boss_diameter,
        boss_height = boss_height,
        insert_hole_diameter = insert_hole_diameter,
        insert_hole_depth = insert_hole_depth,
        front_boss_offset = front_boss_offset,
        back_boss_offset = back_boss_offset,
        boss_overhang = boss_overhang
    );
}
