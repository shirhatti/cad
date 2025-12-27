// Apple TV Retention Bracket for 1U Vented Rack Shelf
//
// A top-down retention bracket that secures an Apple TV 4K to a vented rack shelf.
// Side walls connect via a top plate with ventilation cutout.
// Front and back are completely open for cable access and airflow.
// Bracket attaches using M4/M5 screws from below the shelf, threading into
// heat-set inserts embedded in the bracket's insert bosses.
//
// PRINT ORIENTATION: Print upside-down (top plate on build plate) for best results.
// Rotate 180° around X axis in your slicer before printing.
// No supports needed. Use 3+ perimeters for insert boss strength.

/* [Device Dimensions] */
// Width of the Apple TV 4K
device_width = 93; // [80:1:120]
// Depth of the Apple TV 4K
device_depth = 93; // [80:1:120]
// Height of the Apple TV 4K
device_height = 31; // [20:1:50]

/* [Bracket Dimensions] */
// Overall bracket width (device + clearance + 2×lip_overhang + 2×wall_thickness)
bracket_width = 123; // [100:1:150]
// Overall bracket depth
bracket_depth = 123; // [100:1:150]
// Top plate thickness
top_plate_thickness = 3; // [2:0.5:5]
// Side wall height (matches device height, lip overlaps top of device)
side_wall_height = 31; // [30:1:60]
// Side wall thickness
wall_thickness = 10; // [5:1:15]

/* [Ventilation Cutout] */
// Width of center ventilation cutout
cutout_width = 73; // [50:1:100]
// Depth of center ventilation cutout
cutout_depth = 93; // [50:1:100]

/* [Retention Lip] */
// How far the lip extends inward over the device
lip_overhang = 4; // [2:1:10]
// Thickness of the lip (hangs down from top plate)
lip_thickness = 6; // [2:1:10]
// Corner radius for squircle shape
corner_radius = 10; // [5:1:20]

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
front_insert_offset = 15; // [10:1:30]
// Back insert distance from back edge (center of boss)
back_insert_offset = 15; // [10:1:30]
// Boss overhang from wall OUTWARD (for slot alignment: 8.5mm gives 140mm = 7 × 20mm spacing)
boss_overhang = 8.5; // [0:0.5:20]

/* [Rendering] */
$fa = 1;
$fn = 64;

// Calculate insert hole diameter based on selected size
insert_hole_diameter = (insert_size == "M5") ? m5_hole_diameter : m4_hole_diameter;

// 2D rounded rectangle (squircle)
module rounded_rect(width, depth, radius) {
    offset(r = radius)
    offset(r = -radius)
        square([width, depth], center = true);
}

// Top plate with rounded cutout and integrated retention lip
module top_plate() {
    // Inner dimensions (device cavity)
    inner_width = bracket_width - 2 * wall_thickness;
    inner_depth = bracket_depth;  // Open front/back

    difference() {
        // Outer plate with rounded corners
        translate([bracket_width/2, bracket_depth/2, 0])
            linear_extrude(height = top_plate_thickness)
            rounded_rect(bracket_width, bracket_depth, corner_radius);

        // Center ventilation cutout (smaller than inner, leaves lip)
        translate([bracket_width/2, bracket_depth/2, -0.5])
            linear_extrude(height = top_plate_thickness + 1)
            rounded_rect(inner_width - 2*lip_overhang, inner_depth - 2*lip_overhang, corner_radius);
    }

    // Retention lip hanging down from top plate
    translate([0, 0, -lip_thickness])
    difference() {
        // Outer boundary of lip (same as inner edge of top plate frame)
        translate([bracket_width/2, bracket_depth/2, 0])
            linear_extrude(height = lip_thickness)
            rounded_rect(inner_width, inner_depth, corner_radius);

        // Inner cutout (device clearance)
        translate([bracket_width/2, bracket_depth/2, -0.5])
            linear_extrude(height = lip_thickness + 1)
            rounded_rect(inner_width - 2*lip_overhang, inner_depth - 2*lip_overhang, corner_radius);
    }
}

// Threaded insert boss with hole for heat-set insert
// Boss sits flush with wall bottom at Z=0, extends upward
module insert_boss() {
    difference() {
        // Cylindrical boss - from shelf level (Z=0) up into wall structure
        cylinder(d = boss_diameter, h = boss_height);

        // Insert hole (from bottom at Z=0, for screw from below shelf)
        translate([0, 0, -0.5])
            cylinder(d = insert_hole_diameter, h = insert_hole_depth + 0.5);
    }
}

// Counterbore cut - applied after boss and flange are combined
module counterbore_cut() {
    counterbore_depth = 1; // Subtle step to indicate insert location
    counterbore_diameter = boss_diameter - 2; // Step around insert hole
    cylinder(d = counterbore_diameter, h = counterbore_depth);
}

// Flange to support insert boss extending OUTWARD (away from device)
// Boss rests on shelf surface, screw from below creates clamping force
// Flange extends full wall height to connect boss to wall structure
module boss_flange(y_pos, is_left) {
    flange_width = boss_overhang + boss_diameter / 2; // Extends to support boss center

    // Flange extends from wall OUTWARD (away from device)
    // Full height from Z=0 (shelf) to side_wall_height
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
    wall_frame_width = 20; // Solid material at front and back of wall
    wall_frame_top = 6; // Solid material at top of wall (connects to top plate)
    wall_frame_bottom = 10; // Solid material at bottom (structural + boss support)

    // Apply counterbore cuts AFTER combining boss and flange geometry
    difference() {
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

        // Counterbore cuts at boss locations (cut from combined geometry)
        translate([boss_x, front_insert_offset, -0.1])
            counterbore_cut();
        translate([boss_x, bracket_depth - back_insert_offset, -0.1])
            counterbore_cut();
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

// Main model - in print orientation (top plate on build plate, bosses pointing up)
// Guard: skip rendering if included by another file (e.g., tests)
if (!is_undef(RENDER_BRACKET) ? RENDER_BRACKET : true) {
    // Rotate 180° around X to flip upside-down, center on XY plane for slicer
    translate([-bracket_width/2, bracket_depth/2, side_wall_height + top_plate_thickness])
        rotate([180, 0, 0])
            bracket();
}
