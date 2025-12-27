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
// Boss overhang from wall INWARD (for slot alignment: 6.25mm gives 177.5mm = 5 × 35.5mm spacing)
boss_overhang = 6.25; // [0:0.5:15]

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
// Boss extends from below the wall up into the wall base for structural strength
module insert_boss() {
    // Total boss height: extends below wall + embedded portion in wall
    boss_embed = 5; // How far boss extends up into wall
    total_height = boss_height + boss_embed;

    difference() {
        // Cylindrical boss - extends from below wall into wall base
        cylinder(d = boss_diameter, h = total_height);

        // Insert hole (from bottom, goes up but not through)
        translate([0, 0, -0.5])
            cylinder(d = insert_hole_diameter, h = insert_hole_depth + 0.5);
    }
}

// Flange to support insert boss extending INWARD (toward device)
// This allows the boss to rest on the shelf surface for proper screw clamping
module boss_flange(y_pos, is_left) {
    boss_embed = 5;
    flange_height = boss_embed; // Flange at base of wall
    flange_width = boss_overhang + boss_diameter / 2; // Extends to support boss center

    // Flange extends from wall base INWARD (toward center/device)
    // Left wall: flange goes right (positive X from wall inner edge)
    // Right wall: flange goes left (negative X from wall inner edge)
    translate([is_left ? wall_thickness : -flange_width,
               y_pos - boss_diameter / 2,
               0])
        cube([flange_width, boss_diameter, flange_height]);
}

// Side wall with insert bosses on INWARD flanges at front and back corners
// Bosses extend inward so they rest on shelf surface for proper screw clamping
module side_wall(is_left) {
    // Wall is oriented along Y axis (front to back)
    boss_embed = 5; // Must match value in insert_boss()

    // X position for boss center (overhangs INWARD toward device)
    // Left wall: boss is to the right of wall (wall_thickness + overhang)
    // Right wall: boss is to the left of wall (-overhang, relative to wall origin)
    boss_x = is_left ? (wall_thickness + boss_overhang) : (-boss_overhang);

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

        // Front flange and insert boss (extending INWARD)
        boss_flange(front_insert_offset, is_left);
        translate([boss_x, front_insert_offset, -boss_height])
            insert_boss();

        // Back flange and insert boss (extending INWARD)
        boss_flange(bracket_depth - back_insert_offset, is_left);
        translate([boss_x, bracket_depth - back_insert_offset, -boss_height])
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
// Position so bottom of insert bosses is at Z = 0
translate([0, 0, boss_height])
    bracket();
