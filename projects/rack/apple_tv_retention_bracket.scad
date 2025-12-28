// Apple TV Retention Bracket for 1U Vented Rack Shelf
//
// A top-down retention bracket that secures an Apple TV 4K to a vented rack shelf.
// Side walls on left/right connect via a top plate. Front and back are open.
// Bracket attaches using M4/M5 screws from below the shelf, threading into
// heat-set inserts embedded in the bracket's insert bosses.
//
// PRINT ORIENTATION: Print upside-down (top plate on build plate, bosses up).
// No supports needed. Use 3+ perimeters for insert boss strength.

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
// Derived dimensions (all calculated from parameters above)
// ============================================================

// Lip inner opening (must fit device with clearance)
lip_inner = device_size + clearance;

// Inner cavity size (square, where device sits)
cavity_size = lip_inner + 2 * lip_overhang;

// Outer bracket dimensions
bracket_width = cavity_size + 2 * wall_thickness;  // Walls on left/right
bracket_depth = cavity_size;                        // No walls front/back

// Wall height matches device height (lip overlaps top of device)
wall_height = device_height;

// Total height for print orientation
total_height = wall_height + top_plate_thickness;

// Insert hole diameter based on selected size
insert_hole_diameter = (insert_size == "M5") ? m5_hole_diameter : m4_hole_diameter;

// Boss span for slot alignment verification
boss_span = bracket_width + 2 * boss_overhang;

// ============================================================
// Modules
// ============================================================

// 2D rounded rectangle (squircle)
module rounded_rect(size, radius) {
    offset(r = radius)
    offset(r = -radius)
        square([size, size], center = true);
}

// Top plate with ventilation cutout and retention lip
module top_plate() {
    difference() {
        // Outer plate
        translate([bracket_width/2, bracket_depth/2, 0])
            linear_extrude(height = top_plate_thickness)
            rounded_rect(cavity_size, corner_radius);

        // Ventilation cutout (same as lip inner)
        translate([bracket_width/2, bracket_depth/2, -0.5])
            linear_extrude(height = top_plate_thickness + 1)
            rounded_rect(lip_inner, corner_radius);
    }

    // Retention lip hanging down
    translate([0, 0, -lip_thickness])
    difference() {
        translate([bracket_width/2, bracket_depth/2, 0])
            linear_extrude(height = lip_thickness)
            rounded_rect(cavity_size, corner_radius);

        translate([bracket_width/2, bracket_depth/2, -0.5])
            linear_extrude(height = lip_thickness + 1)
            rounded_rect(lip_inner, corner_radius);
    }
}

// Threaded insert boss
module insert_boss() {
    difference() {
        cylinder(d = boss_diameter, h = boss_height);
        translate([0, 0, -0.5])
            cylinder(d = insert_hole_diameter, h = insert_hole_depth + 0.5);
    }
}

// Flange supporting boss (full height for support-free printing)
module boss_flange(y_pos, is_left) {
    flange_width = boss_overhang + boss_diameter / 2;
    flange_height = total_height;

    translate([is_left ? -flange_width : wall_thickness,
               y_pos - boss_diameter / 2,
               0])
        cube([flange_width, boss_diameter, flange_height]);
}

// Side wall with bosses
module side_wall(is_left) {
    boss_x = is_left ? -boss_overhang : (wall_thickness + boss_overhang);

    // Wall frame parameters
    frame_width = 20;
    frame_top = 6;
    frame_bottom = 10;

    union() {
        // Hollowed wall
        difference() {
            cube([wall_thickness, bracket_depth, wall_height]);

            translate([-0.5, frame_width, frame_bottom])
                cube([wall_thickness + 1,
                      bracket_depth - 2 * frame_width,
                      wall_height - frame_bottom - frame_top]);
        }

        // Front boss and flange
        boss_flange(front_boss_offset, is_left);
        translate([boss_x, front_boss_offset, 0])
            insert_boss();

        // Back boss and flange
        boss_flange(bracket_depth - back_boss_offset, is_left);
        translate([boss_x, bracket_depth - back_boss_offset, 0])
            insert_boss();
    }
}

// Complete bracket assembly
module bracket() {
    translate([0, 0, wall_height])
        top_plate();

    side_wall(is_left = true);

    translate([bracket_width - wall_thickness, 0, 0])
        side_wall(is_left = false);
}

// ============================================================
// Main model (print orientation: top plate on bed, bosses up)
// ============================================================

// Guard: skip rendering if included by another file (e.g., tests)
if (is_undef(RENDER_BRACKET) ? true : RENDER_BRACKET) {
    // Center on XY, Z starts at 0
    translate([-bracket_width/2, bracket_depth/2, total_height])
        rotate([180, 0, 0])
            bracket();
}
