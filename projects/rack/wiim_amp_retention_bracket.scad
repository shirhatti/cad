// WiiM Amp Retention Bracket for 1U Vented Rack Shelf
//
// A top-down retention bracket that secures a WiiM Amp to a vented rack shelf.
// Side walls connect via a top plate with ventilation cutout.
// Front and back are completely open for port and cable access.
// Bracket attaches using M4/M5 screws from below the shelf, threading into
// heat-set inserts embedded in the bracket's insert bosses.
//
// PRINT ORIENTATION: Print upside-down (top plate on build plate) for best results.
// Rotate 180° around X axis in your slicer before printing.
// No supports needed. Use 3+ perimeters for insert boss strength.

/* [Device Dimensions] */
// Width of the WiiM Amp
device_width = 190; // [100:1:300]
// Depth of the WiiM Amp
device_depth = 190; // [100:1:300]
// Height of the WiiM Amp
device_height = 43; // [20:1:100]

/* [Bracket Dimensions] */
// Overall bracket width (device width + 2 × wall thickness)
bracket_width = 210; // [150:1:350]
// Overall bracket depth
bracket_depth = 210; // [150:1:350]
// Top plate thickness
top_plate_thickness = 3; // [2:0.5:5]
// Side wall height (provides 7mm clearance above 43mm device)
side_wall_height = 50; // [30:1:80]
// Side wall thickness (same as frame border for strength)
wall_thickness = 10; // [5:1:20]

/* [Ventilation Cutout] */
// Width of center ventilation cutout
cutout_width = 170; // [100:1:250]
// Depth of center ventilation cutout
cutout_depth = 190; // [100:1:250]

/* [Threaded Insert Bosses] */
// Insert size: M4 or M5
insert_size = "M4"; // [M4, M5]
// Boss outer diameter
boss_diameter = 12; // [10:1:20]
// Boss height (extends below wall bottom)
boss_height = 10; // [8:1:15]
// M4 insert hole diameter (typical for heat-set inserts)
m4_hole_diameter = 5.6; // [5.0:0.1:6.0]
// M5 insert hole diameter (typical for heat-set inserts)
m5_hole_diameter = 6.4; // [6.0:0.1:7.0]
// Insert hole depth
insert_hole_depth = 8; // [6:1:12]
// Front insert distance from front edge (center of boss)
front_insert_offset = 20; // [10:1:40]
// Back insert distance from back edge (center of boss)
back_insert_offset = 12; // [10:1:40]

/* [Rendering] */
$fa = 1;
$fn = 64;

// Calculate insert hole diameter based on selected size
insert_hole_diameter = (insert_size == "M5") ? m5_hole_diameter : m4_hole_diameter;

// Top plate with center ventilation cutout
// Creates a rectangular frame with left/right rails and front/back crossbars
module top_plate() {
    difference() {
        // Outer plate
        cube([bracket_width, bracket_depth, top_plate_thickness]);

        // Center ventilation cutout
        translate([(bracket_width - cutout_width) / 2,
                   (bracket_depth - cutout_depth) / 2,
                   -0.5])
            cube([cutout_width, cutout_depth, top_plate_thickness + 1]);
    }
}

// Threaded insert boss with hole for heat-set insert
module insert_boss() {
    difference() {
        // Cylindrical boss
        cylinder(d = boss_diameter, h = boss_height);

        // Insert hole (from bottom, doesn't go all the way through)
        translate([0, 0, -0.5])
            cylinder(d = insert_hole_diameter, h = insert_hole_depth + 0.5);
    }
}

// Side wall with insert bosses at front and back corners
module side_wall() {
    // Wall is oriented along Y axis (front to back)
    union() {
        // Main wall body
        cube([wall_thickness, bracket_depth, side_wall_height]);

        // Front insert boss - centered in wall thickness
        translate([wall_thickness / 2, front_insert_offset, -boss_height])
            insert_boss();

        // Back insert boss - centered in wall thickness
        translate([wall_thickness / 2, bracket_depth - back_insert_offset, -boss_height])
            insert_boss();
    }
}

// Complete bracket assembly
module bracket() {
    // Top plate sits at top of side walls
    translate([0, 0, side_wall_height])
        top_plate();

    // Left side wall (at X = 0)
    translate([0, 0, 0])
        side_wall();

    // Right side wall (at X = bracket_width - wall_thickness)
    translate([bracket_width - wall_thickness, 0, 0])
        side_wall();
}

// Main model
// Position so bottom of insert bosses is at Z = 0
translate([0, 0, boss_height])
    bracket();
