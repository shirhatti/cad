// WiiM Amp Retention Bracket for 1U Vented Rack Shelf
//
// A top-down retention bracket that secures a WiiM Amp to a vented rack shelf
// by clamping over the device and anchoring through the shelf's ventilation slots.

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
// Overall bracket depth (device depth + 2 × wall thickness)
bracket_depth = 210; // [150:1:350]
// Top plate thickness
top_plate_thickness = 3; // [2:0.5:5]
// Side wall height (should provide clearance above device)
side_wall_height = 50; // [30:1:80]
// Side wall thickness
wall_thickness = 3; // [2:0.5:6]
// Frame border width around center cutout
frame_border = 10; // [5:1:20]

/* [Ventilation Cutout] */
// Width of center ventilation cutout
cutout_width = 150; // [100:1:250]
// Depth of center ventilation cutout
cutout_depth = 150; // [100:1:250]

/* [Cable Opening] */
// Width of cable opening in side walls
cable_opening_width = 160; // [100:1:250]
// Height of cable opening from bottom of wall
cable_opening_height = 40; // [20:1:60]

/* [Anchor Tabs] */
// Length of anchor tab (extends outward)
tab_length = 25; // [15:1:35]
// Width of anchor tab
tab_width = 8; // [6:1:12]
// Thickness of anchor tab
tab_thickness = 3; // [2:0.5:5]
// Barb height for snap-fit
barb_height = 1.5; // [0.5:0.25:3]
// Barb length
barb_length = 5; // [3:0.5:10]
// Tab inset from corner
tab_inset = 15; // [5:1:30]

/* [Print Settings] */
// Small value for clean CSG operations
$fa = 1;
$fn = 32;

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

module side_wall(length, with_cable_opening = false) {
    difference() {
        // Main wall
        cube([length, wall_thickness, side_wall_height]);

        // Cable opening
        if (with_cable_opening) {
            translate([(length - cable_opening_width) / 2,
                       -0.5,
                       0])
                cube([cable_opening_width,
                      wall_thickness + 1,
                      cable_opening_height]);
        }
    }
}

module anchor_tab() {
    // Main tab body
    cube([tab_width, tab_length, tab_thickness]);

    // Snap-fit barb on underside
    translate([tab_width / 2 - barb_length / 2,
               tab_length - barb_length,
               -barb_height])
        cube([barb_length, barb_length, barb_height]);
}

module side_wall_with_tabs(length, tab_positions) {
    union() {
        // Main wall
        side_wall(length, with_cable_opening = true);

        // Add anchor tabs at specified positions
        for (pos = tab_positions) {
            translate([pos, 0, -tab_thickness])
                anchor_tab();
        }
    }
}

module bracket() {
    union() {
        // Top plate
        top_plate();

        // Front wall (along X axis)
        translate([0, 0, top_plate_thickness])
            side_wall_with_tabs(
                bracket_width,
                [tab_inset, bracket_width - tab_inset - tab_width]
            );

        // Back wall (along X axis)
        translate([0, bracket_depth - wall_thickness, top_plate_thickness])
            side_wall_with_tabs(
                bracket_width,
                [tab_inset, bracket_width - tab_inset - tab_width]
            );

        // Left wall (along Y axis)
        translate([0, wall_thickness, top_plate_thickness])
            rotate([0, 0, -90])
                side_wall(bracket_depth - 2 * wall_thickness, with_cable_opening = false);

        // Right wall (along Y axis)
        translate([bracket_width - wall_thickness, wall_thickness, top_plate_thickness])
            rotate([0, 0, -90])
                side_wall(bracket_depth - 2 * wall_thickness, with_cable_opening = false);
    }
}

// Main model
bracket();
