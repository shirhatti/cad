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
device_height = 63; // [20:1:100]

/* [Bracket Dimensions] */
// Overall bracket width (device width + 2 × wall thickness)
bracket_width = 210; // [150:1:350]
// Overall bracket depth
bracket_depth = 210; // [150:1:350]
// Top plate thickness
top_plate_thickness = 3; // [2:0.5:5]
// Side wall height (provides 7mm clearance above 63mm device)
side_wall_height = 70; // [30:1:100]
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
// Boss overhang from wall OUTWARD (for slot alignment: 6.5mm gives 213mm = 6 × 35.5mm spacing)
boss_overhang = 6.5; // [0:0.5:15]

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
// Boss sits flush with wall bottom at Z=0, extends upward
// Includes countersink to indicate insert location
module insert_boss() {
    countersink_depth = 2; // Depth of visual indicator
    countersink_diameter = insert_hole_diameter + 4; // Visible chamfer around hole

    difference() {
        // Cylindrical boss - from shelf level (Z=0) up into wall structure
        cylinder(d = boss_diameter, h = boss_height);

        // Insert hole (from bottom at Z=0, for screw from below shelf)
        translate([0, 0, -0.5])
            cylinder(d = insert_hole_diameter, h = insert_hole_depth + 0.5);

        // Countersink at bottom (Z=0) to indicate insert location
        cylinder(d1 = countersink_diameter, d2 = insert_hole_diameter,
                 h = countersink_depth);
    }
}

// Flange to support insert boss extending OUTWARD (away from device)
// Boss rests on shelf surface, screw from below creates clamping force
// Flange extends full wall height to connect boss to wall structure
module boss_flange(y_pos, is_left) {
    flange_width = boss_overhang + boss_diameter / 2; // Extends to support boss center

    // Flange extends from wall OUTWARD (away from device)
    // Full height from Z=0 (shelf) to wall_frame_bottom (where solid wall starts)
    // Left wall: flange goes left (negative X)
    // Right wall: flange goes right (positive X from wall outer edge)
    translate([is_left ? -flange_width : wall_thickness,
               y_pos - boss_diameter / 2,
               0])
        cube([flange_width, boss_diameter, side_wall_height]);
}

// Side wall with insert bosses on OUTWARD flanges at front and back corners
// Bosses extend outward (over shelf vent area), everything sits flush on shelf at Z=0
module side_wall(is_left) {
    // X position for boss center (overhangs OUTWARD away from device)
    // Left wall: boss is to the left of wall (-overhang)
    // Right wall: boss is to the right of wall (wall_thickness + overhang)
    boss_x = is_left ? (-boss_overhang) : (wall_thickness + boss_overhang);

    // Wall hollowing parameters
    wall_frame_width = 25; // Solid material at front and back of wall
    wall_frame_top = 8; // Solid material at top of wall (connects to top plate)
    wall_frame_bottom = 10; // Solid material at bottom (structural + boss support)

    union() {
        // Hollowed wall body - frame with cutout in middle
        difference() {
            cube([wall_thickness, bracket_depth, side_wall_height]);

            // Cutout in middle of wall (leave frame around edges)
            translate([-0.5,
                       wall_frame_width,
                       wall_frame_bottom])
                cube([wall_thickness + 1,
                      bracket_depth - 2 * wall_frame_width,
                      side_wall_height - wall_frame_bottom - wall_frame_top]);
        }

        // Front flange and insert boss (extending OUTWARD, flush with wall bottom)
        boss_flange(front_insert_offset, is_left);
        translate([boss_x, front_insert_offset, 0])
            insert_boss();

        // Back flange and insert boss (extending OUTWARD, flush with wall bottom)
        boss_flange(bracket_depth - back_insert_offset, is_left);
        translate([boss_x, bracket_depth - back_insert_offset, 0])
            insert_boss();
    }
}

// Complete bracket assembly
module bracket() {
    // Top plate sits at top of side walls
    translate([0, 0, side_wall_height])
        top_plate();

    // Left side wall (at X = 0, bosses overhang to the left)
    translate([0, 0, 0])
        side_wall(is_left = true);

    // Right side wall (at X = bracket_width - wall_thickness, bosses overhang to the right)
    translate([bracket_width - wall_thickness, 0, 0])
        side_wall(is_left = false);
}

// Main model
// Everything sits flush on shelf at Z = 0
bracket();
